require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Axum analyzer (tree-sitter port). Each `.rs` file is parsed once
  # with the vendored Rust grammar; route registrations are picked up
  # by walking `call_expression` nodes whose function is a
  # `field_expression` named `route`. Handler bodies are matched
  # against a same-file `function_item` index so callee extraction
  # shares the parsed tree instead of re-scanning the file with
  # regexes and a body-text wrapper.
  class Axum < RustEngine
    alias UtoipaScopedKey = Tuple(String, String, String)
    alias UtoipaNestEdge = Tuple(UtoipaScopedKey, String)
    alias NestScopedKey = Tuple(String, String, String)
    alias NestEdge = Tuple(NestScopedKey, String)
    alias HandlerContext = NamedTuple(params: Array(Param), callees: Array(Noir::RustCalleeExtractor::Entry))
    alias ByteRange = Tuple(Int32, Int32)

    # Verbs accepted as the inner handler call (`get(...)`, `post(...)`,
    # …). Anything outside this set is treated as `GET` to match the
    # legacy fallback the regex analyzer used. `any` covers
    # `axum::routing::any(handler)` — a verb-agnostic registration
    # commonly used for WebSocket upgrades and reverse-proxy fallbacks.
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options", "any"}

    # Method emitted for service-shaped registrations (`route_service`,
    # `nest_service`, `fallback_service`). Services aren't bound to a
    # specific HTTP method — `tower-http::services::ServeDir` accepts
    # whatever the client sends — so we mirror axum's `any` verb.
    SERVICE_METHOD = "ANY"

    # utoipa-axum routes handlers by attribute, not by a `.route()` call:
    # `#[utoipa::path(get, path = "/x")]` on the handler fn, then
    # `OpenApiRouter::new().routes(routes!(mod::handler))`. The router is
    # mounted with `.nest("/api/v1/x", mod_routes::create_routes())`, so the
    # real URL is the nest prefix + the attribute path. `analyze` builds a
    # `{base_path, module, handler_leaf} => [prefix]` index up front (resolving the
    # cross-file `.nest(prefix, fn())` chain through the `routes!()`
    # collectors); `analyze_file` then emits each `#[utoipa::path]` handler
    # at its composed URL.
    @utoipa_prefix : Hash(UtoipaScopedKey, Array(String))? = nil
    # Cross-file `.nest("/p", router_var)` where `let router_var = mod::fn()`
    # (or `.nest("/p", mod::fn())`) mounts a sub-router whose builder fn lives
    # in another file. Keyed `{base, module, fn_leaf} => [prefix]`; resolved in
    # `analyze` and consumed per-file so the mounted fn's own `.route()` calls
    # pick up the prefix instead of emitting at the root.
    @cross_nest_prefix : Hash(NestScopedKey, Array(String))? = nil
    @external_handler_context_cache = {} of String => HandlerContext
    @external_handler_miss_cache = Set(String).new
    @external_handler_context_cache_mutex = Mutex.new

    def analyze
      @utoipa_prefix = build_utoipa_prefix_index
      @cross_nest_prefix = build_cross_nest_index
      @external_handler_context_cache_mutex.synchronize do
        @external_handler_context_cache.clear
        @external_handler_miss_cache.clear
      end
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      # Path-based test filtering now lives in
      # `RustEngine#parallel_file_scan` (see #1569 history). The
      # remaining `analyze_file` work is the cfg(test) region pass —
      # axum's source files mix production routes with
      # `#[cfg(test)] mod tests { ... }` blocks, which a path filter
      # alone can't tell apart.
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # `#[cfg(test)] mod tests { ... let app = Router::new().route(...); }`
      # is the canonical place doctests-as-unit-tests register routes in
      # Rust source — axum-extra exercises this heavily. The shared
      # `RustEngine.collect_cfg_test_regions` walks the cfg(test)-gated
      # blocks once per file; we filter route calls whose start byte
      # falls inside.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        handler_context_cache = {} of String => HandlerContext
        router_functions = build_router_function_index(root, source)
        let_router_builders = build_let_call_index(root, source)
        mounted_router_names = collect_mounted_router_names(root, source, test_regions, let_router_builders)
        mounted_router_ranges = mounted_router_value_ranges(root, source, test_regions, let_router_builders)
        nested_router_prefixes = collect_nested_router_prefixes(root, source, test_regions, "", mounted_router_names, let_router_builders)

        # Cross-file nest: a router-builder fn DEFINED in this file is mounted
        # under a path prefix by a `.nest("/p", var=mod::fn())` in another
        # file. Seed it into the same mount machinery (skip its root emission,
        # queue it with the external prefix) so its `.route()` calls compose
        # the prefix exactly like a same-file nested router. Skip ambiguous
        # names: `mounted_router_names` / `router_functions` are bare-name
        # keyed, so a leaf shared by two fns in this file (e.g. svix's
        # top-level `router` and its inner `mod development { fn router }`)
        # would suppress BOTH at the root while the queue re-emits only one —
        # a net loss. Only relocate a fn whose name is unique in the file.
        cross_nest = file_cross_nest_prefixes(path)
        unless cross_nest.empty?
          ambiguous = duplicate_function_names(root, source)
          cross_nest.each do |fn_name, prefixes|
            next unless router_functions.has_key?(fn_name)
            next if ambiguous.includes?(fn_name)
            mounted_router_names.add(fn_name)
            bucket = (nested_router_prefixes[fn_name] ||= [] of String)
            prefixes.each { |p| bucket << p unless bucket.includes?(p) }
          end
        end

        walk_router_builders(root, source, "", test_regions, mounted_router_names, let_router_builders, mounted_router_ranges) do |node, prefix|
          route = extract_route(node, source)
          next unless route

          path_str, handlers = route
          path_str = join_paths(prefix, path_str) unless prefix.empty?
          handlers.each do |raw_verb, handler_name|
            # `axum::routing::any(handler)` and service mounts emit
            # the verb "ANY" — fan out into the canonical seven so
            # SARIF / Postman / OpenAPI consumers see real HTTP
            # methods rather than a non-HTTP "ANY" string.
            RustEngine.fan_out_verbs(raw_verb).each do |verb|
              details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
              endpoint = Endpoint.new(path_str, verb, details)
              extract_path_params(path_str, endpoint)

              if handler_name
                attach_handler_context(endpoint, function_index, source, path, handler_name, include_callee, handler_context_cache)
              end

              endpoints << endpoint
            end
          end
        end

        processed_mounts = Set(String).new
        mount_queue = [] of Tuple(String, String)
        nested_router_prefixes.each do |router_name, prefixes|
          prefixes.each { |prefix| mount_queue << {router_name, prefix} }
        end

        mount_index = 0
        # Defensive bound: a router graph with a cycle (or a bare-name
        # collision that resolves a nested mount back to its own builder)
        # would otherwise grow the queue forever with an ever-deeper prefix.
        # Real router trees are tiny; this cap only trips on pathological
        # input and keeps the analyzer from hanging.
        mount_limit = 5000
        while mount_index < mount_queue.size && mount_index < mount_limit
          router_name, prefix = mount_queue[mount_index]
          mount_index += 1

          mount_key = "#{router_name}\0#{prefix}"
          next if processed_mounts.includes?(mount_key)
          processed_mounts.add(mount_key)

          router_function = router_functions[router_name]?
          next unless router_function

          walk_router_builders(router_function, source, prefix, test_regions, Set(String).new, let_router_builders) do |node, active_prefix|
            route = extract_route(node, source)
            next unless route

            path_str, handlers = route
            path_str = join_paths(active_prefix, path_str) unless active_prefix.empty?
            handlers.each do |raw_verb, handler_name|
              RustEngine.fan_out_verbs(raw_verb).each do |verb|
                details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
                endpoint = Endpoint.new(path_str, verb, details)
                extract_path_params(path_str, endpoint)

                if handler_name
                  attach_handler_context(endpoint, function_index, source, path, handler_name, include_callee, handler_context_cache)
                end

                endpoints << endpoint
              end
            end
          end

          collect_nested_router_prefixes(router_function, source, test_regions, prefix, Set(String).new, let_router_builders).each do |nested_name, prefixes|
            # A router whose body nests another router resolved (by bare name)
            # back to itself — e.g. `user_routes::create_routes` nesting
            # `token_routes::create_routes`, both leaf `create_routes` — would
            # re-queue itself at an ever-deeper prefix. Such a same-name
            # self-mount can't be told apart from a true cycle, so skip it;
            # the distinct sub-router is still covered by the utoipa index.
            next if nested_name == router_name
            prefixes.each do |nested_prefix|
              nested_key = "#{nested_name}\0#{nested_prefix}"
              mount_queue << {nested_name, nested_prefix} unless processed_mounts.includes?(nested_key)
            end
          end
        end

        # utoipa-axum `#[utoipa::path(...)]` attribute handlers (registered
        # via `routes!()`, not `.route()`), composed with their OpenApiRouter
        # nest prefix.
        if source.includes?("utoipa::path")
          collect_utoipa_endpoints(root, source, path, test_regions, include_callee, function_index, handler_context_cache, endpoints)
        end
      end

      endpoints
    end

    # Field-call names whose extracted shape `extract_route` knows
    # how to read. `route_service`, `nest_service`, and the two
    # `fallback*` variants surface in roughly half of all real-world
    # axum apps (static-file mounts, SPA fallbacks, websocket upgrades).
    ROUTER_EMIT_NAMES = Set{
      "route", "route_service", "nest_service", "fallback", "fallback_service",
      # aide's `ApiRouter` (OpenAPI companion, used by svix and many
      # axum apps) mirrors `.route` with `.api_route(path, mr)` and
      # `.api_route_with(path, mr, transform_closure)`.
      "api_route", "api_route_with",
    }

    BUILDER_ROUTE_EMIT_NAMES = Set{
      "get", "post", "put", "delete", "patch", "head", "options", "any",
      "unauthenticated_get", "unauthenticated_post", "unauthenticated_put",
      "unauthenticated_delete", "unauthenticated_patch", "unauthenticated_head",
      "unauthenticated_options", "unauthenticated_any",
    }

    private def router_emit?(call : LibTreeSitter::TSNode, source : String) : Bool
      name = field_call_name(call, source)
      return false unless name
      # `fallback`/`fallback_service` are common method names on non-router
      # types and emit a path-less `/*`; require a plausibly-router receiver to
      # avoid phantom endpoints from e.g. `Config{..}.fallback(handler)`.
      if name == "fallback" || name == "fallback_service"
        return router_chain_receiver?(call, source)
      end
      return true if ROUTER_EMIT_NAMES.includes?(name)
      BUILDER_ROUTE_EMIT_NAMES.includes?(name) && route_builder_receiver?(call, source)
    end

    # Conservative receiver check: reject only clearly-non-router receivers
    # (struct literals, arrays, scalar literals); accept router variables,
    # fields, self, and any call chain (real routers are `Router::new()...` or a
    # router variable, so this keeps zero false negatives on those forms).
    private def router_chain_receiver?(call : LibTreeSitter::TSNode, source : String) : Bool
      fn = Noir::TreeSitter.field(call, "function")
      return false unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
      recv = Noir::TreeSitter.field(fn, "value")
      return false unless recv
      case Noir::TreeSitter.node_type(recv)
      when "struct_expression", "array_expression",
           "integer_literal", "float_literal", "string_literal",
           "boolean_literal", "char_literal", "unit_expression"
        false
      else
        true
      end
    end

    # Walks Axum router builder chains with an active path prefix.
    # This keeps ordinary chained `.route(...)` behaviour while also
    # applying `.nest("/api", Router::new().route(...))` prefixes to
    # inline nested routers instead of emitting those inner routes at
    # the root.
    private def walk_router_builders(node : LibTreeSitter::TSNode,
                                     source : String,
                                     prefix : String,
                                     test_regions : Array(Tuple(Int32, Int32)),
                                     mounted_router_names : Set(String),
                                     let_router_builders : Hash(String, LibTreeSitter::TSNode),
                                     skip_ranges : Array(ByteRange) = [] of ByteRange,
                                     &block : LibTreeSitter::TSNode, String ->)
      return if prefix.empty? && node_inside_byte_ranges?(node, skip_ranges)

      if prefix.empty? && Noir::TreeSitter.node_type(node) == "function_item"
        if name = function_name(node, source)
          return if mounted_router_names.includes?(name)
        end
      end

      if Noir::TreeSitter.node_type(node) == "call_expression"
        return if RustEngine.inside_test_region?(node, test_regions)

        # `.route`, `.route_service`, `.nest_service`, and
        # `.fallback` / `.fallback_service` all register endpoints;
        # `extract_route` knows how to read each shape and returns
        # `nil` for anything else. Treating them uniformly here keeps
        # the receiver-chain walk single-pass.
        if router_emit?(node, source)
          block.call(node, prefix)
          walk_receiver_chain(node, source, prefix, test_regions, mounted_router_names, let_router_builders, skip_ranges, &block)
          return
        end

        if nest = extract_nest_call(node, source)
          nest_prefix, nested_router = nest
          resolved_router = resolve_router_argument(nested_router, source, let_router_builders)
          walk_receiver_chain(node, source, prefix, test_regions, mounted_router_names, let_router_builders, skip_ranges, &block)
          walk_router_builders(resolved_router, source, join_paths(prefix, nest_prefix), test_regions, mounted_router_names, let_router_builders, &block)
          return
        end

        if merge_arg = extract_merge_call(node, source)
          walk_receiver_chain(node, source, prefix, test_regions, mounted_router_names, let_router_builders, skip_ranges, &block)
          walk_router_builders(merge_arg, source, prefix, test_regions, mounted_router_names, let_router_builders, skip_ranges, &block)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_router_builders(child, source, prefix, test_regions, mounted_router_names, let_router_builders, skip_ranges, &block)
      end
    end

    private def walk_receiver_chain(call : LibTreeSitter::TSNode,
                                    source : String,
                                    prefix : String,
                                    test_regions : Array(Tuple(Int32, Int32)),
                                    mounted_router_names : Set(String),
                                    let_router_builders : Hash(String, LibTreeSitter::TSNode),
                                    skip_ranges : Array(ByteRange),
                                    &block : LibTreeSitter::TSNode, String ->)
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      receiver = Noir::TreeSitter.field(function, "value")
      return unless receiver
      walk_router_builders(receiver, source, prefix, test_regions, mounted_router_names, let_router_builders, skip_ranges, &block)
    end

    # `.nest("/p", router)` and aide's `.nest_api_service("/p", router)`
    # both mount a sub-router under a path prefix.
    NEST_NAMES = Set{"nest", "nest_api_service"}

    private def extract_nest_call(call : LibTreeSitter::TSNode,
                                  source : String) : Tuple(String, LibTreeSitter::TSNode)?
      name = field_call_name(call, source)
      return unless name && NEST_NAMES.includes?(name)
      args = named_arguments(call)
      return unless args.size >= 2
      prefix = string_literal_text(args[0], source)
      return unless prefix
      {prefix, args[1]}
    end

    private def extract_merge_call(call : LibTreeSitter::TSNode,
                                   source : String) : LibTreeSitter::TSNode?
      return unless field_call_name(call, source) == "merge"
      args = named_arguments(call)
      args.first?
    end

    private def collect_mounted_router_names(root : LibTreeSitter::TSNode,
                                             source : String,
                                             test_regions : Array(Tuple(Int32, Int32)),
                                             let_router_builders : Hash(String, LibTreeSitter::TSNode)) : Set(String)
      names = Set(String).new

      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if RustEngine.inside_test_region?(node, test_regions)

        nest = extract_nest_call(node, source)
        next unless nest

        _, nested_router = nest
        router_name = local_router_function_call_name(resolve_router_argument(nested_router, source, let_router_builders), source)
        names.add(router_name) if router_name
      end

      names
    end

    private def mounted_router_value_ranges(root : LibTreeSitter::TSNode,
                                            source : String,
                                            test_regions : Array(Tuple(Int32, Int32)),
                                            let_router_builders : Hash(String, LibTreeSitter::TSNode)) : Array(ByteRange)
      ranges = [] of ByteRange
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if RustEngine.inside_test_region?(node, test_regions)

        nest = extract_nest_call(node, source)
        next unless nest

        _, nested_router = nest
        next unless Noir::TreeSitter.node_type(nested_router) == "identifier"

        name = Noir::TreeSitter.node_text(nested_router, source)
        if value = let_router_builders[name]?
          range = node_byte_range(value)
          ranges << range unless ranges.includes?(range)
        end
      end
      ranges
    end

    private def collect_nested_router_prefixes(root : LibTreeSitter::TSNode,
                                               source : String,
                                               test_regions : Array(Tuple(Int32, Int32)),
                                               active_prefix : String,
                                               skip_function_names : Set(String),
                                               let_router_builders : Hash(String, LibTreeSitter::TSNode)) : Hash(String, Array(String))
      prefixes = {} of String => Array(String)
      collect_nested_router_prefixes(root, source, test_regions, active_prefix, skip_function_names, let_router_builders, prefixes)
      prefixes
    end

    private def collect_nested_router_prefixes(node : LibTreeSitter::TSNode,
                                               source : String,
                                               test_regions : Array(Tuple(Int32, Int32)),
                                               active_prefix : String,
                                               skip_function_names : Set(String),
                                               let_router_builders : Hash(String, LibTreeSitter::TSNode),
                                               prefixes : Hash(String, Array(String)))
      if Noir::TreeSitter.node_type(node) == "function_item"
        if name = function_name(node, source)
          return if skip_function_names.includes?(name)
        end
      end

      if Noir::TreeSitter.node_type(node) == "call_expression"
        return if RustEngine.inside_test_region?(node, test_regions)

        if nest = extract_nest_call(node, source)
          nest_prefix, nested_router = nest
          mounted_prefix = join_paths(active_prefix, nest_prefix)
          resolved_router = resolve_router_argument(nested_router, source, let_router_builders)

          if router_name = local_router_function_call_name(resolved_router, source)
            entries = prefixes[router_name] ||= [] of String
            entries << mounted_prefix unless entries.includes?(mounted_prefix)
          else
            collect_nested_router_prefixes(resolved_router, source, test_regions, mounted_prefix, skip_function_names, let_router_builders, prefixes)
          end

          walk_receiver_chain_for_mounts(node, source, active_prefix, test_regions, skip_function_names, let_router_builders, prefixes)
          return
        end

        if merge_arg = extract_merge_call(node, source)
          collect_nested_router_prefixes(merge_arg, source, test_regions, active_prefix, skip_function_names, let_router_builders, prefixes)
          walk_receiver_chain_for_mounts(node, source, active_prefix, test_regions, skip_function_names, let_router_builders, prefixes)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_nested_router_prefixes(child, source, test_regions, active_prefix, skip_function_names, let_router_builders, prefixes)
      end
    end

    private def walk_receiver_chain_for_mounts(call : LibTreeSitter::TSNode,
                                               source : String,
                                               active_prefix : String,
                                               test_regions : Array(Tuple(Int32, Int32)),
                                               skip_function_names : Set(String),
                                               let_router_builders : Hash(String, LibTreeSitter::TSNode),
                                               prefixes : Hash(String, Array(String)))
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      receiver = Noir::TreeSitter.field(function, "value")
      return unless receiver
      collect_nested_router_prefixes(receiver, source, test_regions, active_prefix, skip_function_names, let_router_builders, prefixes)
    end

    private def local_router_function_call_name(node : LibTreeSitter::TSNode, source : String) : String?
      call = innermost_router_call(node, source)
      return unless call && Noir::TreeSitter.node_type(call) == "call_expression"
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      function = unwrap_generic_function(function)
      return unless Noir::TreeSitter.node_type(function) == "identifier"

      Noir::TreeSitter.node_text(function, source)
    end

    private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      field ? Noir::TreeSitter.node_text(field, source) : nil
    end

    private def route_builder_receiver?(call : LibTreeSitter::TSNode, source : String) : Bool
      fn_node = Noir::TreeSitter.field(call, "function")
      return false unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"

      receiver = Noir::TreeSitter.field(fn_node, "value")
      receiver ? route_builder_chain?(receiver, source) : false
    end

    private def route_builder_chain?(node : LibTreeSitter::TSNode, source : String) : Bool
      case Noir::TreeSitter.node_type(node)
      when "call_expression"
        return true if route_builder_constructor_call?(node, source)

        fn_node = Noir::TreeSitter.field(node, "function")
        return false unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"

        field = Noir::TreeSitter.field(fn_node, "field")
        receiver = Noir::TreeSitter.field(fn_node, "value")
        return false unless field && receiver

        field_name = Noir::TreeSitter.node_text(field, source)
        BUILDER_ROUTE_EMIT_NAMES.includes?(field_name) && route_builder_chain?(receiver, source)
      else
        false
      end
    end

    private def route_builder_constructor_call?(call : LibTreeSitter::TSNode, source : String) : Bool
      fn_node = Noir::TreeSitter.field(call, "function")
      return false unless fn_node

      text = Noir::TreeSitter.node_text(fn_node, source)
      !!text.match(/(?:^|::)[A-Za-z_]\w*(?:RouteBuilder|RouterBuilder)::new$/)
    end

    # Returns `{path, [{http_method, handler_name?}, ...]}` for a valid
    # router-emit call, or `nil` when the shape doesn't match.
    # Dispatches by the field-call name:
    # * `route(path, verb(handler))` — usual case; returns one or
    #   more verbs from the `get(...)`/`post(...)` chain.
    # * `route_service(path, svc)` / `nest_service(prefix, svc)` —
    #   service-shaped mounts; verb is `ANY` because tower services
    #   don't restrict methods.
    # * `fallback(handler)` / `fallback_service(svc)` — catch-all
    #   registration; we emit at `/*` so the endpoint surfaces in
    #   downstream tooling without colliding with a real path.
    private def extract_route(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(Tuple(String, String?)))?
      kind = field_call_name(call, source)
      return unless kind

      case kind
      when "route", "api_route", "api_route_with"
        # `.route(path, mr)`, aide `.api_route(path, mr)`, and
        # `.api_route_with(path, mr, transform)` all carry the path in
        # arg 0 and the method-router in arg 1 (the trailing transform
        # closure of `api_route_with` is ignored).
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        return if named.size < 2
        path = string_literal_text(named[0], source)
        return unless path
        {path, decode_handler(named[1], source)}
      when "route_service"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        return if named.size < 1
        path = string_literal_text(named[0], source)
        return unless path
        {path, [{SERVICE_METHOD, nil.as(String?)}]}
      when "nest_service"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        return if named.size < 1
        prefix = string_literal_text(named[0], source)
        return unless prefix
        {join_paths(prefix, "/*"), [{SERVICE_METHOD, nil.as(String?)}]}
      when "fallback", "fallback_service"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        # Router-level `.fallback(handler)` (one arg) and the rare
        # path-scoped `.fallback("/api/*", handler)` (two args, only
        # available on `MethodRouter`) — bail on anything else.
        handler = named.last?.try { |n| callable_text(n, source) }
        {"/*", [{SERVICE_METHOD, handler}]}
      else
        extract_builder_route(kind, call, source)
      end
    end

    private def extract_builder_route(kind : String,
                                      call : LibTreeSitter::TSNode,
                                      source : String) : Tuple(String, Array(Tuple(String, String?)))?
      verb = builder_route_verb(kind)
      return unless verb

      named = named_arguments(call)
      return if named.size < 2

      path = string_literal_text(named[0], source)
      return unless path

      handler = callable_text(named[1], source)
      {path, [{verb, handler}]}
    end

    private def builder_route_verb(kind : String) : String?
      name = kind.starts_with?("unauthenticated_") ? kind["unauthenticated_".size..] : kind
      return name.upcase if HTTP_VERBS.includes?(name)
      nil
    end

    # `get(handler)` → `{[{"GET", "handler"}]}`.
    # `get(handler).post(other)` → `{[{"GET", "handler"}, {"POST", "other"}]}`.
    # The chain is left-folded by tree-sitter, so we walk back from
    # the outermost call to the innermost `get(...)` collecting verbs
    # in declaration order. Every verb keeps its own handler so
    # callee / AI-context output does not leak one method's body onto
    # its sibling method at the same path. Falls
    # back to a single GET endpoint when the shape doesn't match.
    private def decode_handler(node : LibTreeSitter::TSNode, source : String) : Array(Tuple(String, String?))
      handlers = [] of Tuple(String, String?)

      cursor = node
      while Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn_node = Noir::TreeSitter.field(cursor, "function")
        break unless fn_node
        case Noir::TreeSitter.node_type(fn_node)
        when "identifier", "scoped_identifier"
          # Innermost: `get(handler)` or aide's `get_with(handler, op)`.
          verb = normalize_method_verb(Noir::TreeSitter.node_text(fn_node, source).split("::").last)
          if verb
            handlers.unshift({verb, first_callable_argument(cursor, source)})
          end
          break
        when "field_expression"
          # Chained: `<inner>.post(...)` / `.post_with(...)`. Field is
          # the verb. Non-verb layers (`.layer(...)`, `.route_layer(...)`)
          # are transparent.
          field = Noir::TreeSitter.field(fn_node, "field")
          if field
            verb = normalize_method_verb(Noir::TreeSitter.node_text(field, source))
            if verb
              handlers.unshift({verb, first_callable_argument(cursor, source)})
            end
          end
          inner = Noir::TreeSitter.field(fn_node, "value")
          break unless inner
          cursor = inner
        else
          break
        end
      end

      handlers << {"GET", nil.as(String?)} if handlers.empty?
      handlers
    end

    # Map a method-router constructor name to its canonical HTTP verb,
    # or `nil` if it isn't one. Handles plain axum verbs (`get`, `post`,
    # … `any`) and aide's operation-annotated `*_with` variants
    # (`get_with`, `post_with`, …). Returns the upcased verb.
    private def normalize_method_verb(name : String) : String?
      verb = name.downcase
      verb = verb[0...-"_with".size] if verb.ends_with?("_with")
      HTTP_VERBS.includes?(verb) ? verb.upcase : nil
    end

    private def first_callable_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        if text = callable_text(child, source)
          return text
        end
      end
      nil
    end

    private def callable_text(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "identifier", "scoped_identifier"
        Noir::TreeSitter.node_text(node, source)
      when "generic_function"
        inner = Noir::TreeSitter.field(node, "function")
        inner ? callable_text(inner, source) : nil
      end
    end

    private def named_arguments(call : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      args = Noir::TreeSitter.field(call, "arguments")
      return [] of LibTreeSitter::TSNode unless args
      named_children(args)
    end

    private def named_children(node : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named
    end

    private def join_paths(prefix : String, path : String) : String
      "#{prefix.rstrip('/')}/#{path.lstrip('/')}"
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:([A-Za-z_]\w*)/) do |match|
        push_path_param(endpoint, match[1])
      end

      route.scan(/\{\**([A-Za-z_]\w*)\}/) do |match|
        push_path_param(endpoint, match[1])
      end

      route.scan(%r{/\*([A-Za-z_]\w*)}) do |match|
        push_path_param(endpoint, match[1])
      end
    end

    private def push_path_param(endpoint : Endpoint, name : String)
      endpoint.push_param(Param.new(name, "", "path"))
    end

    private def extract_function_params(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      header_vars = Set(String).new
      cookie_vars = Set(String).new

      params = Noir::TreeSitter.field(function, "parameters")
      if params
        Noir::TreeSitter.each_named_child(params) do |param|
          text = Noir::TreeSitter.node_text(param, source)
          extract_function_param_text(text, endpoint)
          if binding = param_binding_name(text)
            header_vars.add(binding) if text.includes?("HeaderMap")
            cookie_vars.add(binding) if text.includes?("CookieJar")
          end
        end
      end

      body = Noir::TreeSitter.field(function, "body")
      return unless body

      collect_header_and_cookie_params(body, source, endpoint, header_vars, cookie_vars)
    end

    private def extract_function_param_text(text : String, endpoint : Endpoint)
      endpoint.push_param(Param.new("query", "", "query")) if extractor_param?(text, "Query")
      endpoint.push_param(Param.new("body", "", "json")) if extractor_param?(text, "Json")
      endpoint.push_param(Param.new("form", "", "form")) if extractor_param?(text, "Form")
    end

    # Precompiled per extractor type; interpolated regex literals here would
    # be recompiled on every function parameter.
    EXTRACTOR_PARAM_RES = {
      "Query" => {/Query\s*\(\s*[^)]+\s*\)/, /:\s*(?:[A-Za-z_]\w*::)*Query\b/},
      "Json"  => {/Json\s*\(\s*[^)]+\s*\)/, /:\s*(?:[A-Za-z_]\w*::)*Json\b/},
      "Form"  => {/Form\s*\(\s*[^)]+\s*\)/, /:\s*(?:[A-Za-z_]\w*::)*Form\b/},
    }

    private def extractor_param?(text : String, type_name : String) : Bool
      call_re, type_re = EXTRACTOR_PARAM_RES[type_name]
      text.includes?("#{type_name}<") ||
        !!text.match(call_re) ||
        !!text.match(type_re)
    end

    private def param_binding_name(text : String) : String?
      match = text.match(/^\s*(?:mut\s+)?([A-Za-z_]\w*)\s*:/)
      match.try(&.[1])
    end

    private def collect_header_and_cookie_params(body : LibTreeSitter::TSNode,
                                                 source : String,
                                                 endpoint : Endpoint,
                                                 header_vars : Set(String),
                                                 cookie_vars : Set(String))
      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"

        fn_text = call_function_text(call, source)
        next unless fn_text

        if header_read_call?(fn_text, header_vars)
          first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source).try do |name|
            endpoint.push_param(Param.new(name, "", "header")) if header_name?(name)
          end
        elsif cookie_read_call?(fn_text, cookie_vars)
          first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source).try do |name|
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    private def header_read_call?(fn_text : String, header_vars : Set(String)) : Bool
      return true if fn_text.ends_with?(".headers().get")

      header_vars.any? { |name| fn_text == "#{name}.get" }
    end

    private def cookie_read_call?(fn_text : String, cookie_vars : Set(String)) : Bool
      return true if fn_text.ends_with?(".cookie")

      cookie_vars.any? { |name| fn_text == "#{name}.get" }
    end

    private def header_name?(name : String) : Bool
      name.includes?("-") || name.in?(%w[Authorization Content-Type Accept])
    end

    private def call_function_text(call : LibTreeSitter::TSNode, source : String) : String?
      function = Noir::TreeSitter.field(call, "function")
      function ? Noir::TreeSitter.node_text(function, source) : nil
    end

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      return string_literal_text(node, source) if Noir::TreeSitter.node_type(node) == "string_literal"

      Noir::TreeSitter.each_named_child(node) do |child|
        if text = first_string_literal_text(child, source)
          return text
        end
      end
      nil
    end

    private def string_literal_text(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "string_literal"
      # tree-sitter-rust splits a literal with escapes into multiple children
      # ("/a\tb" -> string_content "/a", escape_sequence "\t", string_content "b").
      # Concatenate every segment instead of keeping only the last one.
      parts = [] of String
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_content", "escape_sequence"
          parts << Noir::TreeSitter.node_text(child, source)
        end
      end
      parts.empty? ? nil : parts.join
    end

    private def build_router_function_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      index = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name = function_name(node, source)
        body_node = Noir::TreeSitter.field(node, "body")
        next unless name && body_node
        index[name] = body_node unless index.has_key?(name)
      end
      index
    end

    private def function_name(function : LibTreeSitter::TSNode, source : String) : String?
      name_node = Noir::TreeSitter.field(function, "name")
      name_node ? Noir::TreeSitter.node_text(name_node, source) : nil
    end

    private def build_function_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      index = {} of String => LibTreeSitter::TSNode
      build_function_index(root, source, [] of String, index)
      index
    end

    private def build_function_index(node : LibTreeSitter::TSNode,
                                     source : String,
                                     scope : Array(String),
                                     index : Hash(String, LibTreeSitter::TSNode))
      case Noir::TreeSitter.node_type(node)
      when "function_item"
        name_node = Noir::TreeSitter.field(node, "name")
        body_node = Noir::TreeSitter.field(node, "body")
        return unless name_node && body_node

        name = Noir::TreeSitter.node_text(name_node, source)
        if scope.empty?
          index[name] = node unless index.has_key?(name)
        else
          qualified_name = "#{scope.join("::")}::#{name}"
          index[qualified_name] = node unless index.has_key?(qualified_name)
        end
      when "mod_item"
        name_node = Noir::TreeSitter.field(node, "name")
        body_node = Noir::TreeSitter.field(node, "body")
        return unless name_node && body_node

        nested_scope = scope + [Noir::TreeSitter.node_text(name_node, source)]
        Noir::TreeSitter.each_named_child(body_node) do |child|
          build_function_index(child, source, nested_scope, index)
        end
      else
        Noir::TreeSitter.each_named_child(node) do |child|
          build_function_index(child, source, scope, index)
        end
      end
    end

    private def attach_handler_context(endpoint : Endpoint,
                                       index : Hash(String, LibTreeSitter::TSNode),
                                       source : String,
                                       path : String,
                                       handler_name : String,
                                       include_callee : Bool,
                                       handler_context_cache : Hash(String, HandlerContext))
      cache_key = "#{path}\0#{handler_name}\0#{include_callee}"
      if context = handler_context_cache[cache_key]?
        attach_cached_handler_context(endpoint, context)
        return
      end

      if function = function_for_handler(index, handler_name)
        context = handler_context_for_function(function, source, path, include_callee)
        handler_context_cache[cache_key] = context
        attach_cached_handler_context(endpoint, context)
        return
      end

      attach_external_handler_context(endpoint, handler_name, path, include_callee, handler_context_cache)
    end

    private def function_for_handler(index : Hash(String, LibTreeSitter::TSNode), handler_name : String) : LibTreeSitter::TSNode?
      return index[handler_name]? if index.has_key?(handler_name)
      return if handler_name.includes?("::")

      index[handler_name]?
    end

    private def callee_entries_for_function(function : LibTreeSitter::TSNode,
                                            source : String,
                                            path : String) : Array(Noir::RustCalleeExtractor::Entry)
      body = Noir::TreeSitter.field(function, "body")
      return [] of Noir::RustCalleeExtractor::Entry unless body

      Noir::RustCalleeExtractorTS.callees_in_body(body, source, path)
    end

    private def handler_context_for_function(function : LibTreeSitter::TSNode,
                                             source : String,
                                             path : String,
                                             include_callee : Bool) : HandlerContext
      endpoint = Endpoint.new("", "GET")
      extract_function_params(function, source, endpoint)
      callees = include_callee ? callee_entries_for_function(function, source, path) : [] of Noir::RustCalleeExtractor::Entry
      {params: endpoint.params, callees: callees}
    end

    private def attach_cached_handler_context(endpoint : Endpoint, context : HandlerContext)
      context[:params].each do |param|
        endpoint.push_param(param)
      end
      attach_rust_callees(endpoint, context[:callees]) unless context[:callees].empty?
    end

    private def attach_external_handler_context(endpoint : Endpoint,
                                                handler_name : String,
                                                current_path : String,
                                                include_callee : Bool,
                                                handler_context_cache : Hash(String, HandlerContext))
      parts = handler_name.split("::").reject(&.empty?)
      return if parts.size < 2

      function_name = parts.last
      module_parts = parts[0...-1]

      candidate_module_paths(current_path, module_parts).each do |candidate|
        next unless File.exists?(candidate)

        cache_key = "#{candidate}\0#{function_name}\0#{include_callee}"
        if context = handler_context_cache[cache_key]?
          attach_cached_handler_context(endpoint, context)
          return
        end

        if context = cached_external_handler_context(candidate, function_name, include_callee)
          handler_context_cache[cache_key] = context
          attach_cached_handler_context(endpoint, context)
          return
        end
      end
    end

    private def cached_external_handler_context(candidate : String,
                                                function_name : String,
                                                include_callee : Bool) : HandlerContext?
      cache_key = "#{candidate}\0#{function_name}\0#{include_callee}"
      miss_key = "#{candidate}\0#{function_name}"

      @external_handler_context_cache_mutex.synchronize do
        return @external_handler_context_cache[cache_key]? if @external_handler_context_cache.has_key?(cache_key)
        return if @external_handler_miss_cache.includes?(miss_key)

        context = parse_external_handler_context(candidate, function_name, include_callee)
        if context
          @external_handler_context_cache[cache_key] = context
        else
          @external_handler_miss_cache.add(miss_key)
        end
        context
      end
    end

    private def parse_external_handler_context(candidate : String,
                                               function_name : String,
                                               include_callee : Bool) : HandlerContext?
      source = read_file_content(candidate)
      context = nil.as(HandlerContext?)

      Noir::TreeSitter.parse_rust(source) do |root|
        index = build_function_index(root, source)
        if function = index[function_name]?
          context = handler_context_for_function(function, source, candidate, include_callee)
        end
      end

      context
    end

    private def candidate_module_paths(current_path : String, module_parts : Array(String)) : Array(String)
      return [] of String if module_parts.empty?

      base_dir, parts = module_base_dir(current_path, module_parts)
      return [] of String if parts.empty?

      module_path = parts.join("/")
      [
        File.join(base_dir, "#{module_path}.rs"),
        File.join(base_dir, module_path, "mod.rs"),
      ]
    end

    private def module_base_dir(current_path : String, module_parts : Array(String)) : Tuple(String, Array(String))
      first = module_parts.first
      rest = module_parts[1..]? || [] of String

      case first
      when "crate"
        {crate_src_dir(current_path), rest}
      when "self"
        {current_module_dir(current_path), rest}
      when "super"
        {File.dirname(current_module_dir(current_path)), rest}
      else
        {current_module_dir(current_path), module_parts}
      end
    end

    private def current_module_dir(current_path : String) : String
      File.dirname(current_path)
    end

    private def crate_src_dir(current_path : String) : String
      marker = "/src/"
      if idx = current_path.rindex(marker)
        current_path[0, idx + marker.size - 1]
      else
        File.dirname(current_path)
      end
    end

    # ── utoipa-axum #[utoipa::path] support ──────────────────────────

    UTOIPA_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options", "trace"}

    # Emit an endpoint for every `#[utoipa::path(method, path = "/x")]`
    # handler in the file, composed with the OpenApiRouter nest prefix the
    # handler is registered under.
    private def collect_utoipa_endpoints(root : LibTreeSitter::TSNode, source : String, path : String,
                                         test_regions : Array(Tuple(Int32, Int32)), include_callee : Bool,
                                         function_index : Hash(String, LibTreeSitter::TSNode),
                                         handler_context_cache : Hash(String, HandlerContext),
                                         endpoints : Array(Endpoint))
      file_mod = primary_module(path)
      base = configured_base_for(path)
      each_attribute_pair(root) do |attr_item, function|
        next if RustEngine.inside_test_region?(attr_item, test_regions)
        route = extract_utoipa_attr(attr_item, source)
        next unless route
        methods, attr_path = route
        leaf = function_name(function, source)
        # Only emit handlers actually registered through `routes!()` (so they
        # appear in the nest index). A `#[utoipa::path]` handler wired up with
        # a manual `.route(...)` instead — common when a body-limit layer is
        # needed — is emitted by the builder pass already; emitting it here
        # too would duplicate it at the bare, prefix-less attribute path.
        prefixes = leaf ? @utoipa_prefix.try { |prefixes| prefixes[{base, file_mod, leaf}]? } : nil
        next if prefixes.nil? || prefixes.empty?
        root_path = attr_path.empty? || attr_path == "/"
        urls = prefixes.map do |p|
          if p.empty?
            root_path ? "/" : ensure_leading_slash(attr_path)
          elsif root_path
            p # `path = "/"` registers at the nest root, no trailing slash
          else
            join_paths(p, attr_path)
          end
        end
        attr_row = Noir::TreeSitter.node_start_row(attr_item) + 1
        methods.each do |verb|
          urls.each do |url|
            details = Details.new(PathInfo.new(path, attr_row))
            endpoint = Endpoint.new(url, verb, details)
            extract_path_params(url, endpoint)
            if leaf
              attach_handler_context(endpoint, function_index, source, path, leaf, include_callee, handler_context_cache)
            end
            endpoints << endpoint
          end
        end
      end
    end

    # `#[utoipa::path(get, path = "/x")]` / `#[utoipa::path(method(get, head),
    # path = "/x")]` → `{[VERBS], "/x"}`. Returns nil for other attributes.
    private def extract_utoipa_attr(attr_item : LibTreeSitter::TSNode, source : String) : Tuple(Array(String), String)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr
      name = attr_path_name(attr, source)
      return unless name && (name == "utoipa::path" || name.ends_with?("::utoipa::path") || name == "path")
      args = Noir::TreeSitter.field(attr, "arguments")
      return unless args
      text = Noir::TreeSitter.node_text(args, source)
      path_m = text.match(/\bpath\s*=\s*"([^"]*)"/)
      return unless path_m
      head = text.split(/\bpath\s*=/, 2).first
      methods = extract_utoipa_methods(head)
      return if methods.empty?
      {methods, path_m[1]}
    end

    private def extract_utoipa_methods(head : String) : Array(String)
      verbs = [] of String
      if mm = head.match(/\bmethod\s*\(\s*([^)]*)\)/)
        mm[1].scan(/[A-Za-z]+/) do |m|
          v = m[0].downcase
          verbs << v.upcase if UTOIPA_VERBS.includes?(v)
        end
      end
      if verbs.empty?
        head.scan(/[A-Za-z]+/) do |m|
          v = m[0].downcase
          verbs << v.upcase if verbs.empty? && UTOIPA_VERBS.includes?(v)
        end
      end
      verbs.uniq
    end

    private def attr_path_name(attr : LibTreeSitter::TSNode, source : String) : String?
      result = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          result = Noir::TreeSitter.node_text(child, source)
          break
        end
      end
      result
    end

    # Cross-file `.nest*("/p", X)` resolution. `X` is either a direct
    # router-builder call `mod::make_router()` or a `let`-bound variable whose
    # initializer is that call (possibly decorated with `.with_state(...)`).
    # The mounted builder may only merge other routers (svix's
    # `v1::router().merge(endpoints::health::router())...`), so this builds a
    # small function graph and propagates prefixes through `.merge(child)` and
    # nested `.nest("/child", child)` edges.
    private def build_cross_nest_index : Hash(NestScopedKey, Array(String))
      direct = Hash(NestScopedKey, Array(String)).new
      edges = Hash(NestScopedKey, Array(NestEdge)).new

      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        src = read_file_content(fpath)
        next unless src.includes?(".nest(") || src.includes?(".nest_api_service(") || src.includes?(".merge(")
        base = configured_base_for(fpath)
        begin
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            let_calls = build_let_call_index(root, src)
            collect_cross_router_edges(root, src, base, primary_module(fpath), test_regions, let_calls, edges)
            walk(root) do |node|
              next unless Noir::TreeSitter.node_type(node) == "call_expression"
              next if RustEngine.inside_test_region?(node, test_regions)
              name = field_call_name(node, src)
              next unless name && NEST_NAMES.includes?(name)
              args = named_arguments(node)
              next unless args.size >= 2
              prefix = string_literal_text(args[0], src)
              next unless prefix
              call = resolve_router_call(args[1], src, let_calls)
              next unless call
              mod, leaf = scoped_module_leaf(call, src)
              next unless mod && leaf
              key = {base, mod, leaf}
              bucket = (direct[key] ||= [] of String)
              bucket << prefix unless bucket.includes?(prefix)
            end
          end
        rescue e
          logger.debug "axum cross-nest index error #{fpath}: #{e}"
        end
      end

      index = Hash(NestScopedKey, Array(String)).new
      direct.each do |key, prefixes|
        prefixes.each do |prefix|
          add_cross_prefix(index, key, prefix)
          propagate_cross_prefix(key, prefix, edges, index, Set(NestScopedKey).new)
        end
      end
      index
    end

    private def collect_cross_router_edges(root : LibTreeSitter::TSNode,
                                           source : String,
                                           base : String,
                                           file_mod : String,
                                           test_regions : Array(Tuple(Int32, Int32)),
                                           let_calls : Hash(String, LibTreeSitter::TSNode),
                                           edges : Hash(NestScopedKey, Array(NestEdge)))
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        next if RustEngine.inside_test_region?(node, test_regions)

        name_node = Noir::TreeSitter.field(node, "name")
        body = Noir::TreeSitter.field(node, "body")
        next unless name_node && body

        parent = {base, file_mod, Noir::TreeSitter.node_text(name_node, source)}
        walk(body) do |call|
          next unless Noir::TreeSitter.node_type(call) == "call_expression"
          next if RustEngine.inside_test_region?(call, test_regions)

          field = field_call_name(call, source)
          next unless field

          case field
          when "merge"
            args = named_arguments(call)
            next if args.empty?
            child = resolve_router_call(args[0], source, let_calls)
            next unless child
            add_cross_edge(edges, parent, child, "", source, base)
          else
            next unless NEST_NAMES.includes?(field)
            args = named_arguments(call)
            next unless args.size >= 2
            prefix = string_literal_text(args[0], source)
            next unless prefix
            child = resolve_router_call(args[1], source, let_calls)
            next unless child
            add_cross_edge(edges, parent, child, prefix, source, base)
          end
        end
      end
    end

    private def add_cross_edge(edges : Hash(NestScopedKey, Array(NestEdge)),
                               parent : NestScopedKey,
                               child_call : LibTreeSitter::TSNode,
                               prefix : String,
                               source : String,
                               base : String)
      mod, leaf = scoped_module_leaf(child_call, source)
      return unless mod && leaf

      child = {base, mod, leaf}
      edge = {child, prefix}
      bucket = (edges[parent] ||= [] of NestEdge)
      bucket << edge unless bucket.includes?(edge)
    end

    private def propagate_cross_prefix(parent : NestScopedKey,
                                       prefix : String,
                                       edges : Hash(NestScopedKey, Array(NestEdge)),
                                       index : Hash(NestScopedKey, Array(String)),
                                       stack : Set(NestScopedKey))
      return if stack.includes?(parent)
      stack.add(parent)
      if children = edges[parent]?
        children.each do |child, child_prefix|
          composed = child_prefix.empty? ? prefix : join_paths(prefix, child_prefix)
          add_cross_prefix(index, child, composed)
          propagate_cross_prefix(child, composed, edges, index, stack)
        end
      end
      stack.delete(parent)
    end

    private def add_cross_prefix(index : Hash(NestScopedKey, Array(String)),
                                 key : NestScopedKey,
                                 prefix : String)
      bucket = (index[key] ||= [] of String)
      bucket << prefix unless bucket.includes?(prefix)
    end

    # Cross-nest prefixes for fns DEFINED in `path` (keyed by leaf name),
    # resolved from the project-wide index by this file's base + module.
    private def file_cross_nest_prefixes(path : String) : Hash(String, Array(String))
      result = Hash(String, Array(String)).new
      idx = @cross_nest_prefix
      return result if idx.nil? || idx.empty?
      base = configured_base_for(path)
      mod = primary_module(path)
      idx.each do |key, prefixes|
        kbase, kmod, kleaf = key
        result[kleaf] = prefixes if kbase == base && kmod == mod
      end
      result
    end

    # Function names that appear more than once in a file (e.g. a top-level
    # `fn router` plus a nested `mod x { fn router }`). Bare-name routing
    # machinery can't tell them apart, so cross-nest relocation skips them.
    private def duplicate_function_names(root : LibTreeSitter::TSNode, source : String) : Set(String)
      seen = Set(String).new
      dups = Set(String).new
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        if name = function_name(node, source)
          dups.add(name) unless seen.add?(name)
        end
      end
      dups
    end

    # Map `let VAR = <call>` bindings to their call node so a `.nest("/p", VAR)`
    # can be resolved back to the router-builder fn it calls.
    private def build_let_call_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      index = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "let_declaration"
        pattern = Noir::TreeSitter.field(node, "pattern")
        value = Noir::TreeSitter.field(node, "value")
        next unless pattern && value
        next unless Noir::TreeSitter.node_type(pattern) == "identifier"
        next unless Noir::TreeSitter.node_type(value) == "call_expression"
        name = Noir::TreeSitter.node_text(pattern, source)
        index[name] = value unless index.has_key?(name)
      end
      index
    end

    private def resolve_router_argument(arg : LibTreeSitter::TSNode,
                                        source : String,
                                        let_calls : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode
      return arg unless Noir::TreeSitter.node_type(arg) == "identifier"

      let_calls[Noir::TreeSitter.node_text(arg, source)]? || arg
    end

    private def node_byte_range(node : LibTreeSitter::TSNode) : ByteRange
      {
        LibTreeSitter.ts_node_start_byte(node).to_i,
        LibTreeSitter.ts_node_end_byte(node).to_i,
      }
    end

    private def node_inside_byte_ranges?(node : LibTreeSitter::TSNode, ranges : Array(ByteRange)) : Bool
      return false if ranges.empty?

      start_byte = LibTreeSitter.ts_node_start_byte(node).to_i
      ranges.any? { |s, e| start_byte >= s && start_byte < e }
    end

    private def innermost_router_call(call : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      return unless Noir::TreeSitter.node_type(call) == "call_expression"

      fn = Noir::TreeSitter.field(call, "function")
      return call unless fn

      fn = unwrap_generic_function(fn)
      return call unless Noir::TreeSitter.node_type(fn) == "field_expression"

      receiver = Noir::TreeSitter.field(fn, "value")
      return call unless receiver && Noir::TreeSitter.node_type(receiver) == "call_expression"

      innermost_router_call(receiver, source) || receiver
    end

    private def unwrap_generic_function(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode
      return node unless Noir::TreeSitter.node_type(node) == "generic_function"

      Noir::TreeSitter.field(node, "function") || node
    end

    # The router-builder call behind a `.nest` second argument: the arg itself
    # when it's already a call, or the initializer of the `let` it names.
    private def resolve_router_call(arg : LibTreeSitter::TSNode, source : String,
                                    let_calls : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      case Noir::TreeSitter.node_type(arg)
      when "call_expression"
        arg
      when "identifier"
        let_calls[Noir::TreeSitter.node_text(arg, source)]?
      end
    end

    # `{module, leaf}` of a call's function path. `webui::make_webui_router` ->
    # `{"webui", "make_webui_router"}`; a bare `make_router()` -> `{nil, "make_router"}`
    # (no module to disambiguate the defining file, so the caller skips it).
    private def scoped_module_leaf(call : LibTreeSitter::TSNode, source : String) : Tuple(String?, String?)
      base_call = innermost_router_call(call, source)
      return {nil, nil} unless base_call

      fn = Noir::TreeSitter.field(base_call, "function")
      return {nil, nil} unless fn
      fn = unwrap_generic_function(fn)
      case Noir::TreeSitter.node_type(fn)
      when "scoped_identifier"
        segs = Noir::TreeSitter.node_text(fn, source).split("::")
        leaf = segs[-1]?
        return {nil, nil} if leaf.nil? || leaf == "new"
        {segs.size >= 2 ? segs[-2] : nil, leaf}
      when "identifier"
        {nil, Noir::TreeSitter.node_text(fn, source)}
      else
        {nil, nil}
      end
    end

    # Build `{base_path, module, handler_leaf} => [nest prefix]` from the OpenApiRouter
    # composition: `.nest("/p", mod_routes::create_routes())` mounts a
    # collector fn, whose `.routes(routes!(mod::handler))` calls list the
    # handlers. The nest chain is threaded across files (and through nested
    # `.nest()` inside collectors).
    private def build_utoipa_prefix_index : Hash(UtoipaScopedKey, Array(String))
      nest_edges = Hash(UtoipaScopedKey, Array(UtoipaNestEdge)).new
      nested_set = Set(UtoipaScopedKey).new
      fn_routes = Hash(UtoipaScopedKey, Array(Tuple(String, String?))).new

      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        base = configured_base_for(fpath)
        src = read_file_content(fpath)
        next unless src.includes?("OpenApiRouter") || src.includes?(".routes(")
        file_mod = primary_module(fpath)
        begin
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            collect_utoipa_fns(root, src, base, file_mod, test_regions, nest_edges, nested_set, fn_routes)
          end
        rescue e
          logger.debug "axum utoipa index scan error #{fpath}: #{e}"
        end
      end

      ext = Hash(UtoipaScopedKey, Array(String)).new
      nested_set.each { |f| resolve_nest_external(f, nest_edges, nested_set, ext, Set(UtoipaScopedKey).new) }

      index = Hash(UtoipaScopedKey, Array(String)).new
      fn_routes.each do |fnkey, leaves|
        prefixes = ext[fnkey]? || [""]
        leaves.each do |leaf, ref_mod|
          key = {fnkey[0], ref_mod || fnkey[1], leaf}
          bucket = (index[key] ||= [] of String)
          prefixes.each { |p| bucket << p unless bucket.includes?(p) }
        end
      end
      index
    end

    private def collect_utoipa_fns(root : LibTreeSitter::TSNode, source : String, base : String, file_mod : String,
                                   test_regions : Array(Tuple(Int32, Int32)),
                                   nest_edges : Hash(UtoipaScopedKey, Array(UtoipaNestEdge)),
                                   nested_set : Set(UtoipaScopedKey),
                                   fn_routes : Hash(UtoipaScopedKey, Array(Tuple(String, String?))))
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "function_item"
        next if RustEngine.inside_test_region?(n, test_regions)
        name_node = Noir::TreeSitter.field(n, "name")
        body = Noir::TreeSitter.field(n, "body")
        next unless name_node && body
        fn_key = {base, file_mod, Noir::TreeSitter.node_text(name_node, source)}
        walk(body) do |c|
          case Noir::TreeSitter.node_type(c)
          when "macro_invocation"
            collect_utoipa_routes_leaves(c, source, fn_key, fn_routes)
          when "call_expression"
            fnf = Noir::TreeSitter.field(c, "function")
            next unless fnf && Noir::TreeSitter.node_type(fnf) == "field_expression"
            fld = Noir::TreeSitter.field(fnf, "field")
            next unless fld && Noir::TreeSitter.node_text(fld, source) == "nest"
            args = Noir::TreeSitter.field(c, "arguments")
            next unless args
            named = [] of LibTreeSitter::TSNode
            Noir::TreeSitter.each_named_child(args) { |a| named << a }
            next if named.size < 2
            prefix = string_literal_text(named[0], source)
            next unless prefix
            child_key = nest_child_key(named[1], source, base, file_mod)
            next unless child_key
            (nest_edges[fn_key] ||= [] of UtoipaNestEdge) << {child_key, prefix}
            nested_set.add(child_key)
          end
        end
      end
    end

    private def nest_child_key(node : LibTreeSitter::TSNode, source : String, base : String, file_mod : String) : UtoipaScopedKey?
      return unless Noir::TreeSitter.node_type(node) == "call_expression"
      fn = Noir::TreeSitter.field(node, "function")
      return unless fn
      case Noir::TreeSitter.node_type(fn)
      when "scoped_identifier"
        segs = Noir::TreeSitter.node_text(fn, source).split("::")
        segs.size >= 2 ? {base, segs[-2], segs[-1]} : {base, file_mod, segs[-1]}
      when "identifier"
        {base, file_mod, Noir::TreeSitter.node_text(fn, source)}
      end
    end

    private def collect_utoipa_routes_leaves(macro_node : LibTreeSitter::TSNode, source : String,
                                             fn_key : UtoipaScopedKey, fn_routes : Hash(UtoipaScopedKey, Array(Tuple(String, String?))))
      mname = Noir::TreeSitter.field(macro_node, "macro")
      return unless mname && Noir::TreeSitter.node_text(mname, source).split("::").last == "routes"
      tt = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(macro_node) { |c| tt = c if Noir::TreeSitter.node_type(c) == "token_tree" }
      return unless token_tree = tt
      text = Noir::TreeSitter.node_text(token_tree, source)
      inner = text.strip
      inner = inner[1..] if inner.starts_with?('(') || inner.starts_with?('[')
      inner = inner[0...-1] if inner.ends_with?(')') || inner.ends_with?(']')
      inner = inner.gsub(/\/\/[^\n]*/, " ").gsub(%r{/\*.*?\*/}m, " ")
      bucket = (fn_routes[fn_key] ||= [] of Tuple(String, String?))
      inner.split(',').each do |raw|
        m = raw.match(/([A-Za-z_]\w*(?:\s*::\s*[A-Za-z_]\w*)*)/)
        next unless m
        segs = m[1].split("::").map(&.strip)
        bucket << {segs[-1], segs.size >= 2 ? segs[-2] : nil}
      end
    end

    private def resolve_nest_external(name : UtoipaScopedKey,
                                      edges : Hash(UtoipaScopedKey, Array(UtoipaNestEdge)),
                                      nested_set : Set(UtoipaScopedKey),
                                      ext : Hash(UtoipaScopedKey, Array(String)),
                                      stack : Set(UtoipaScopedKey)) : Array(String)
      if cached = ext[name]?
        return cached
      end
      return [""] unless nested_set.includes?(name)
      return [] of String if stack.includes?(name)
      stack.add(name)
      result = [] of String
      edges.each do |parent, lst|
        lst.each do |child, prefix|
          next unless child == name
          resolve_nest_external(parent, edges, nested_set, ext, stack).each do |pe|
            joined = join_nest(pe, prefix)
            result << joined unless result.includes?(joined)
          end
        end
      end
      stack.delete(name)
      final = result.empty? ? [""] : result
      ext[name] = final
      final
    end

    private def join_nest(a : String, b : String) : String
      return b if a.empty?
      return a if b.empty?
      "#{a.rstrip('/')}/#{b.lstrip('/')}"
    end

    private def ensure_leading_slash(p : String) : String
      p.starts_with?("/") ? p : "/#{p}"
    end

    private def primary_module(path : String) : String
      base = File.basename(path, ".rs")
      dir = File.dirname(path)
      case base
      when "mod"
        File.basename(dir)
      when "lib", "main"
        parent = File.basename(dir)
        parent == "src" ? File.basename(File.dirname(dir)) : parent
      else
        base
      end
    end

    private def find_named_child(node : LibTreeSitter::TSNode, type : String) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(node) do |child|
        return child if Noir::TreeSitter.node_type(child) == type
      end
      nil
    end

    # Walk `node`'s children pairing each `attribute_item` with the
    # `function_item` it decorates (skipping doc comments / other attrs).
    private def each_attribute_pair(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode, LibTreeSitter::TSNode ->)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named.each_with_index do |child, idx|
        if Noir::TreeSitter.node_type(child) == "attribute_item"
          (idx + 1...named.size).each do |i|
            nxt = named[i]
            case Noir::TreeSitter.node_type(nxt)
            when "function_item"
              block.call(child, nxt)
              break
            when "attribute_item", "line_comment", "block_comment"
              next
            else
              break
            end
          end
        end
        each_attribute_pair(child, &block)
      end
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
