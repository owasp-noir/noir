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
        function_index = include_callee ? build_function_index(root, source) : Hash(String, LibTreeSitter::TSNode).new
        router_functions = build_router_function_index(root, source)
        mounted_router_names = collect_mounted_router_names(root, source, test_regions)
        nested_router_prefixes = collect_nested_router_prefixes(root, source, test_regions, "", mounted_router_names)

        walk_router_builders(root, source, "", test_regions, mounted_router_names) do |node, prefix|
          route = extract_route(node, source)
          next unless route

          path_str, methods, handler_name = route
          path_str = join_paths(prefix, path_str) unless prefix.empty?
          methods.each do |raw_verb|
            # `axum::routing::any(handler)` and service mounts emit
            # the verb "ANY" — fan out into the canonical seven so
            # SARIF / Postman / OpenAPI consumers see real HTTP
            # methods rather than a non-HTTP "ANY" string.
            RustEngine.fan_out_verbs(raw_verb).each do |verb|
              details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
              endpoint = Endpoint.new(path_str, verb, details)

              if include_callee && handler_name && (body_node = function_index[handler_name]?)
                entries = Noir::RustCalleeExtractorTS.callees_in_body(body_node, source, path)
                attach_rust_callees(endpoint, entries)
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
        while mount_index < mount_queue.size
          router_name, prefix = mount_queue[mount_index]
          mount_index += 1

          mount_key = "#{router_name}\0#{prefix}"
          next if processed_mounts.includes?(mount_key)
          processed_mounts.add(mount_key)

          router_function = router_functions[router_name]?
          next unless router_function

          walk_router_builders(router_function, source, prefix, test_regions, Set(String).new) do |node, active_prefix|
            route = extract_route(node, source)
            next unless route

            path_str, methods, handler_name = route
            path_str = join_paths(active_prefix, path_str) unless active_prefix.empty?
            methods.each do |raw_verb|
              RustEngine.fan_out_verbs(raw_verb).each do |verb|
                details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
                endpoint = Endpoint.new(path_str, verb, details)

                if include_callee && handler_name && (body_node = function_index[handler_name]?)
                  entries = Noir::RustCalleeExtractorTS.callees_in_body(body_node, source, path)
                  attach_rust_callees(endpoint, entries)
                end

                endpoints << endpoint
              end
            end
          end

          collect_nested_router_prefixes(router_function, source, test_regions, prefix, Set(String).new).each do |nested_name, prefixes|
            prefixes.each do |nested_prefix|
              nested_key = "#{nested_name}\0#{nested_prefix}"
              mount_queue << {nested_name, nested_prefix} unless processed_mounts.includes?(nested_key)
            end
          end
        end
      end

      endpoints
    end

    # Field-call names whose extracted shape `extract_route` knows
    # how to read. `route_service`, `nest_service`, and the two
    # `fallback*` variants surface in roughly half of all real-world
    # axum apps (static-file mounts, SPA fallbacks, websocket upgrades).
    ROUTER_EMIT_NAMES = Set{"route", "route_service", "nest_service", "fallback", "fallback_service"}

    private def router_emit?(call : LibTreeSitter::TSNode, source : String) : Bool
      name = field_call_name(call, source)
      return false unless name
      ROUTER_EMIT_NAMES.includes?(name)
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
                                     &block : LibTreeSitter::TSNode, String ->)
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
          walk_receiver_chain(node, source, prefix, test_regions, mounted_router_names, &block)
          return
        end

        if nest = extract_nest_call(node, source)
          nest_prefix, nested_router = nest
          walk_receiver_chain(node, source, prefix, test_regions, mounted_router_names, &block)
          walk_router_builders(nested_router, source, join_paths(prefix, nest_prefix), test_regions, mounted_router_names, &block)
          return
        end

        if merge_arg = extract_merge_call(node, source)
          walk_receiver_chain(node, source, prefix, test_regions, mounted_router_names, &block)
          walk_router_builders(merge_arg, source, prefix, test_regions, mounted_router_names, &block)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_router_builders(child, source, prefix, test_regions, mounted_router_names, &block)
      end
    end

    private def walk_receiver_chain(call : LibTreeSitter::TSNode,
                                    source : String,
                                    prefix : String,
                                    test_regions : Array(Tuple(Int32, Int32)),
                                    mounted_router_names : Set(String),
                                    &block : LibTreeSitter::TSNode, String ->)
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      receiver = Noir::TreeSitter.field(function, "value")
      return unless receiver
      walk_router_builders(receiver, source, prefix, test_regions, mounted_router_names, &block)
    end

    private def extract_nest_call(call : LibTreeSitter::TSNode,
                                  source : String) : Tuple(String, LibTreeSitter::TSNode)?
      return unless field_call_name(call, source) == "nest"
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
                                             test_regions : Array(Tuple(Int32, Int32))) : Set(String)
      names = Set(String).new

      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if RustEngine.inside_test_region?(node, test_regions)

        nest = extract_nest_call(node, source)
        next unless nest

        _, nested_router = nest
        router_name = router_function_call_name(nested_router, source)
        names.add(router_name) if router_name
      end

      names
    end

    private def collect_nested_router_prefixes(root : LibTreeSitter::TSNode,
                                               source : String,
                                               test_regions : Array(Tuple(Int32, Int32)),
                                               active_prefix : String,
                                               skip_function_names : Set(String)) : Hash(String, Array(String))
      prefixes = {} of String => Array(String)
      collect_nested_router_prefixes(root, source, test_regions, active_prefix, skip_function_names, prefixes)
      prefixes
    end

    private def collect_nested_router_prefixes(node : LibTreeSitter::TSNode,
                                               source : String,
                                               test_regions : Array(Tuple(Int32, Int32)),
                                               active_prefix : String,
                                               skip_function_names : Set(String),
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

          if router_name = router_function_call_name(nested_router, source)
            entries = prefixes[router_name] ||= [] of String
            entries << mounted_prefix unless entries.includes?(mounted_prefix)
          else
            collect_nested_router_prefixes(nested_router, source, test_regions, mounted_prefix, skip_function_names, prefixes)
          end

          walk_receiver_chain_for_mounts(node, source, active_prefix, test_regions, skip_function_names, prefixes)
          return
        end

        if merge_arg = extract_merge_call(node, source)
          collect_nested_router_prefixes(merge_arg, source, test_regions, active_prefix, skip_function_names, prefixes)
          walk_receiver_chain_for_mounts(node, source, active_prefix, test_regions, skip_function_names, prefixes)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_nested_router_prefixes(child, source, test_regions, active_prefix, skip_function_names, prefixes)
      end
    end

    private def walk_receiver_chain_for_mounts(call : LibTreeSitter::TSNode,
                                               source : String,
                                               active_prefix : String,
                                               test_regions : Array(Tuple(Int32, Int32)),
                                               skip_function_names : Set(String),
                                               prefixes : Hash(String, Array(String)))
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      receiver = Noir::TreeSitter.field(function, "value")
      return unless receiver
      collect_nested_router_prefixes(receiver, source, test_regions, active_prefix, skip_function_names, prefixes)
    end

    private def router_function_call_name(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "call_expression"
      function = Noir::TreeSitter.field(node, "function")
      return unless function

      case Noir::TreeSitter.node_type(function)
      when "identifier"
        Noir::TreeSitter.node_text(function, source)
      when "scoped_identifier"
        name = Noir::TreeSitter.node_text(function, source).split("::").last
        return if name == "new"
        name
      when "generic_function"
        inner = Noir::TreeSitter.field(function, "function")
        return unless inner
        name = Noir::TreeSitter.node_text(inner, source).split("::").last
        return if name == "new"
        name
      end
    end

    private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      field ? Noir::TreeSitter.node_text(field, source) : nil
    end

    # Returns `{path, http_methods, handler_name?}` for a valid
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
    private def extract_route(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String), String?)?
      kind = field_call_name(call, source)
      return unless kind

      case kind
      when "route"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        return if named.size < 2
        path = string_literal_text(named[0], source)
        return unless path
        methods, handler = decode_handler(named[1], source)
        {path, methods, handler}
      when "route_service"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        return if named.size < 1
        path = string_literal_text(named[0], source)
        return unless path
        {path, [SERVICE_METHOD], nil}
      when "nest_service"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        return if named.size < 1
        prefix = string_literal_text(named[0], source)
        return unless prefix
        {join_paths(prefix, "/*"), [SERVICE_METHOD], nil}
      when "fallback", "fallback_service"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = named_children(args)
        # Router-level `.fallback(handler)` (one arg) and the rare
        # path-scoped `.fallback("/api/*", handler)` (two args, only
        # available on `MethodRouter`) — bail on anything else.
        handler = named.last?.try { |n| identifier_text(n, source) }
        {"/*", [SERVICE_METHOD], handler}
      end
    end

    private def identifier_text(node : LibTreeSitter::TSNode, source : String) : String?
      return Noir::TreeSitter.node_text(node, source) if Noir::TreeSitter.node_type(node) == "identifier"
      nil
    end

    # `get(handler)` → `{["GET"], "handler"}`.
    # `get(handler).post(other)` → `{["GET", "POST"], "handler"}`.
    # The chain is left-folded by tree-sitter, so we walk back from
    # the outermost call to the innermost `get(...)` collecting verbs
    # in declaration order. The handler captured is the FIRST
    # handler in the chain — every verb routes to *its own* handler
    # in real Axum code, but the legacy regex analyzer only tracked
    # one and we keep that behaviour for callee attribution. Falls
    # back to a single GET endpoint when the shape doesn't match.
    private def decode_handler(node : LibTreeSitter::TSNode, source : String) : Tuple(Array(String), String?)
      methods = [] of String
      handler : String? = nil

      cursor = node
      while Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn_node = Noir::TreeSitter.field(cursor, "function")
        break unless fn_node
        case Noir::TreeSitter.node_type(fn_node)
        when "identifier"
          # Innermost: `get(handler)`.
          verb = Noir::TreeSitter.node_text(fn_node, source).downcase
          if HTTP_VERBS.includes?(verb)
            methods.unshift(verb.upcase)
          end
          handler ||= first_identifier_argument(cursor, source)
          break
        when "field_expression"
          # Chained: `<inner>.post(...)`. Field is the verb.
          field = Noir::TreeSitter.field(fn_node, "field")
          if field
            verb = Noir::TreeSitter.node_text(field, source).downcase
            methods.unshift(verb.upcase) if HTTP_VERBS.includes?(verb)
          end
          inner = Noir::TreeSitter.field(fn_node, "value")
          break unless inner
          cursor = inner
        else
          break
        end
      end

      methods << "GET" if methods.empty?
      {methods, handler}
    end

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
      end
      nil
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

    private def string_literal_text(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "string_literal"
      content = nil.as(String?)
      Noir::TreeSitter.each_named_child(node) do |child|
        content = Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "string_content"
      end
      content
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
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name_node = Noir::TreeSitter.field(node, "name")
        body_node = Noir::TreeSitter.field(node, "body")
        next unless name_node && body_node
        name = Noir::TreeSitter.node_text(name_node, source)
        # First occurrence wins. axum handlers are rarely overloaded
        # in the same file and the legacy analyzer behaved the same
        # way (first `fn name` match in the line scan).
        index[name] = body_node unless index.has_key?(name)
      end
      index
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
