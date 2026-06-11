require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # actix-web analyzer (tree-sitter port). actix-web wires routes via
  # `#[get("/path")]` / `#[post(...)]` attribute macros that sit as
  # **siblings** of the `function_item` they decorate (this is how
  # tree-sitter-rust models outer attributes — they aren't children of
  # the item they attach to). The analyzer walks every container and
  # pairs each routing attribute with the function_item that follows
  # it, skipping intermediate attribute_items and doc comments.
  class ActixWeb < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}
    alias GlobalFunctionEntry = NamedTuple(name: String, path: String, hints: Array(String), params_text: String?, callees: Array(Noir::RustCalleeExtractor::Entry))

    # Cross-file scope registrations: `web::scope("/auth").service(mod::handler)`
    # frequently mounts a `#[get("/x")]` handler that lives in a *different*
    # file (the scope tree sits in `main.rs` / a router-setup module, the
    # `#[get]` handler in `api/<mod>.rs`). The per-file scope pass below only
    # sees same-file registrations, so those handlers lose their prefix
    # (`/x` instead of `/auth/v1/x`). `analyze` walks every file once up
    # front to record each **module-qualified** `.service(mod::handler)`
    # registration's fully composed prefix; `analyze_file` then falls back to
    # this index when a handler isn't registered in its own file. Only
    # qualified (`mod::handler`) refs are globalised — bare `.service(handler)`
    # refs stay file-local so identically named handlers across the standalone
    # sub-apps of an example monorepo don't cross-contaminate.
    @cross_file_scope_regs : Array(NamedTuple(base: String, ref: String, prefix: String))? = nil

    # Cross-file `.configure()` prefixes. A scope delegates its body to a
    # function in another file: `web::scope("/auth").configure(|cfg|
    # auth_service::configure_server(cfg, ...))` /
    # `web::scope("/api").configure(graphql_server::configure_endpoint)`. The
    # builder routes (`cfg.service(web::resource("/x").route(...))`) live in
    # that function's file, with no visible scope, so they lose the `/auth` /
    # `/api` prefix. `analyze` records each configured fn's scope prefix(es)
    # up front; the builder pass prepends them to routes emitted inside the fn.
    @configure_fn_prefix : Array(NamedTuple(base: String, ref: String, prefix: String, source_path: String))? = nil
    @global_function_index : Array(GlobalFunctionEntry)? = nil
    @project_import_aliases : Hash(String, String)? = nil

    def analyze
      @cross_file_scope_regs = build_cross_file_scope_registrations
      @configure_fn_prefix = build_configure_fn_prefix
      @global_function_index = nil
      @project_import_aliases = nil
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        scoped_services = collect_service_registrations(root, source, test_regions, path)

        each_routing_pair(root) do |attr, function|
          next if RustEngine.inside_test_region?(attr, test_regions)

          route = extract_route(attr, source)
          next unless route
          route_path, methods, attr_row = route

          handler_name = function_name(function, source)
          prefixes = handler_name ? scoped_services[handler_name]? : nil
          # Same-file scope pass found nothing — the handler is mounted
          # cross-file via `.service(mod::handler)`. Resolve its prefix from
          # the global index (module-qualified, so name clashes stay apart).
          if (prefixes.nil? || prefixes.empty?) && handler_name
            prefixes = lookup_cross_file_prefixes(handler_name, path)
          end

          methods.each do |method|
            if prefixes && !prefixes.empty?
              prefixes.each do |prefix|
                endpoint_path = scoped_route_path(prefix, route_path)
                endpoints << build_attribute_endpoint(endpoint_path, method, attr_row, path, function, source, include_callee)
              end
            else
              endpoints << build_attribute_endpoint(route_path, method, attr_row, path, function, source, include_callee)
            end
          end
        end

        # Second pass: `App::new().route("/path", web::<verb>().to(handler))`
        # and `web::resource("/path").route(web::<verb>().to(handler))`
        # registrations. The attribute walk above only catches the
        # `#[get(...)]` macro form, so manual builder-style routes
        # were silently dropped.
        #
        # Real apps nest these under one or more `scope("/api")` /
        # `scope("/v4")` layers (`scope("/a").service(scope("/b")
        # .route(...))`), so a flat receiver-chain walk only sees the
        # innermost scope. `collect_scope_prefixes` threads the prefix
        # top-down through `.service(...)` once per file; the builder
        # pass then looks up each scope/resource call's *fully composed*
        # prefix. Function index lets us follow `.to(handler)` to the
        # handler body for callee enrichment.
        #
        # Skip the whole builder pass (two extra tree walks) on files that
        # have neither a `.route(` nor a `resource(` — the common
        # attribute-macro-only handler file — so the added scope-prefix
        # machinery costs nothing where it can't apply. `resource(` is needed
        # for the verb-less `web::resource("/p").to(handler)` form.
        if source.includes?(".route(") || source.includes?("resource(")
          scope_prefixes = collect_scope_prefixes(root, source, test_regions)
          function_index = build_function_index(root, source)
          # Map each builder route back to the `.configure`d fn that encloses
          # it (only when there is at least one cross-file configure prefix).
          configure_ranges = configure_active? ? build_fn_ranges(root, source) : nil

          walk_calls(root) do |call|
            next if RustEngine.inside_test_region?(call, test_regions)

            if builder_route = extract_builder_route(call, source, scope_prefixes)
              route_path, methods, handler_name = builder_route
              details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(call) + 1))
              configure_route_paths(route_path, call, configure_ranges, path).each do |rp|
                canonical = canonicalize_actix_path(rp)
                methods.each do |raw_verb|
                  RustEngine.fan_out_verbs(raw_verb).each do |verb|
                    endpoint = Endpoint.new(canonical, verb, details)
                    extract_path_params(rp, endpoint)
                    if handler_name
                      attach_builder_handler_context(endpoint, handler_name, function_index, source, path, include_callee)
                    end
                    endpoints << endpoint
                  end
                end
              end
              next
            end

            # `web::resource("/p").to(handler)` (optionally with `.wrap(...)`
            # in between) registers `handler` for any method — actix's
            # verb-less resource form. Emit a single GET so the route
            # surfaces without fanning out seven near-duplicate endpoints.
            if resource_to = extract_resource_to(call, source, scope_prefixes)
              route_path, handler_name = resource_to
              details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(call) + 1))
              configure_route_paths(route_path, call, configure_ranges, path).each do |rp|
                endpoint = Endpoint.new(canonicalize_actix_path(rp), "GET", details)
                extract_path_params(rp, endpoint)
                if handler_name
                  attach_builder_handler_context(endpoint, handler_name, function_index, source, path, include_callee)
                end
                endpoints << endpoint
              end
            end
          end
        end
      end

      endpoints
    end

    private def build_attribute_endpoint(route_path : String,
                                         method : String,
                                         attr_row : Int32,
                                         file_path : String,
                                         function : LibTreeSitter::TSNode,
                                         source : String,
                                         include_callee : Bool) : Endpoint
      details = Details.new(PathInfo.new(file_path, attr_row))
      endpoint = Endpoint.new(canonicalize_actix_path(route_path), method, details)

      extract_path_params(route_path, endpoint)
      extract_function_params(function, source, endpoint)
      attach_handler_callees(function, source, file_path, endpoint) if include_callee

      endpoint
    end

    # Actix attribute routes are commonly mounted with
    # `web::scope("/api").service(handler)`. The attribute itself only
    # carries the local path, so the service registration is needed to
    # avoid emitting `/posts` when the real endpoint is `/api/posts`.
    private def collect_service_registrations(root : LibTreeSitter::TSNode,
                                              source : String,
                                              test_regions : Array(Tuple(Int32, Int32)),
                                              file_path : String) : Hash(String, Array(String))
      registrations = {} of String => Array(String)
      collect_service_registrations(root, source, test_regions, file_path, "", registrations)
      registrations
    end

    private def collect_service_registrations(node : LibTreeSitter::TSNode,
                                              source : String,
                                              test_regions : Array(Tuple(Int32, Int32)),
                                              file_path : String,
                                              active_prefix : String,
                                              registrations : Hash(String, Array(String)))
      if Noir::TreeSitter.node_type(node) == "function_item"
        if name = function_name(node, source)
          if prefixes = lookup_configure_prefixes(name, file_path)
            Noir::TreeSitter.each_named_child(node) do |child|
              prefixes.each do |prefix|
                collect_service_registrations(child, source, test_regions, file_path, scoped_route_path(active_prefix, prefix), registrations)
              end
            end
            return
          end
        end
      end

      if Noir::TreeSitter.node_type(node) == "call_expression"
        return if RustEngine.inside_test_region?(node, test_regions)

        if field_call_name(node, source) == "service"
          args = Noir::TreeSitter.field(node, "arguments")
          return unless args
          named = named_children(args)
          return unless named.size == 1

          function = Noir::TreeSitter.field(node, "function")
          return unless function
          receiver = Noir::TreeSitter.field(function, "value")
          receiver_prefix = receiver ? (extract_scope_prefix(receiver, source) || "") : ""
          service_prefix = scoped_route_path(active_prefix, receiver_prefix)

          if handler_name = service_handler_name(named[0], source)
            push_registration(registrations, handler_name, service_prefix)
          else
            collect_service_registrations(named[0], source, test_regions, file_path, service_prefix, registrations)
          end

          collect_service_registrations(receiver, source, test_regions, file_path, active_prefix, registrations) if receiver
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_service_registrations(child, source, test_regions, file_path, active_prefix, registrations)
      end
    end

    private def push_registration(registrations : Hash(String, Array(String)),
                                  handler_name : String,
                                  prefix : String)
      prefixes = registrations[handler_name] ||= [] of String
      prefixes << prefix unless prefixes.includes?(prefix)
    end

    private def service_handler_name(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "identifier"
        Noir::TreeSitter.node_text(node, source)
      when "scoped_identifier"
        Noir::TreeSitter.node_text(node, source).split("::").last
      end
    end

    # First pass over the whole project: collect every module-qualified
    # `.service(mod::handler)` registration's fully composed scope prefix.
    # Gated to files that actually carry both a `scope(` and a `.service(`
    # (router-setup files) so handler-only files cost nothing here.
    private def build_cross_file_scope_registrations : Array(NamedTuple(base: String, ref: String, prefix: String))
      regs = [] of NamedTuple(base: String, ref: String, prefix: String)
      all_files.each do |path|
        next if File.directory?(path)
        next unless File.exists?(path) && File.extname(path) == ".rs"
        next if RustEngine.test_path?(path)
        base = configured_base_for(path)
        src = read_file_content(path)
        next unless src.includes?("scope(") && src.includes?(".service(")
        begin
          glob_contexts = import_glob_contexts(src)
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            collect_qualified_registrations(root, src, test_regions, "", base, glob_contexts, regs)
          end
        rescue e
          logger.debug "actix cross-file scope scan error #{path}: #{e}"
        end
      end
      regs
    end

    # Mirror of `collect_service_registrations`' prefix threading, but records
    # only **scoped** (`mod::handler`) `.service(...)` args — the cross-file
    # case. Bare-identifier args are left to the per-file pass.
    private def collect_qualified_registrations(node : LibTreeSitter::TSNode,
                                                source : String,
                                                test_regions : Array(Tuple(Int32, Int32)),
                                                active_prefix : String,
                                                base : String,
                                                glob_contexts : Array(String),
                                                regs : Array(NamedTuple(base: String, ref: String, prefix: String)))
      if Noir::TreeSitter.node_type(node) == "call_expression"
        return if RustEngine.inside_test_region?(node, test_regions)

        if field_call_name(node, source) == "service"
          args = Noir::TreeSitter.field(node, "arguments")
          return unless args
          named = named_children(args)
          return unless named.size == 1

          function = Noir::TreeSitter.field(node, "function")
          return unless function
          receiver = Noir::TreeSitter.field(function, "value")
          receiver_prefix = receiver ? (extract_scope_prefix(receiver, source) || "") : ""
          service_prefix = scoped_route_path(active_prefix, receiver_prefix)

          arg = named[0]
          case Noir::TreeSitter.node_type(arg)
          when "scoped_identifier"
            regs << {base: base, ref: Noir::TreeSitter.node_text(arg, source), prefix: service_prefix}
          when "identifier"
            unless service_prefix.empty? || glob_contexts.empty?
              name = Noir::TreeSitter.node_text(arg, source)
              glob_contexts.each do |context|
                regs << {base: base, ref: "#{context}::#{name}", prefix: service_prefix}
              end
            end
          else
            collect_qualified_registrations(arg, source, test_regions, service_prefix, base, glob_contexts, regs)
          end

          collect_qualified_registrations(receiver, source, test_regions, active_prefix, base, glob_contexts, regs) if receiver
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_qualified_registrations(child, source, test_regions, active_prefix, base, glob_contexts, regs)
      end
    end

    # Resolve a handler function's cross-file scope prefix(es). Matches the
    # global index module-aware: the segment before the leaf in the
    # registration ref (`api_keys::get_api_keys` → `api_keys`) must equal the
    # handler file's module (its filename stem, or the parent dir for
    # `mod.rs`/`lib.rs`/`main.rs`). When no module matches we return nil
    # rather than guess, so a leaf shared by two modules never borrows the
    # wrong prefix.
    private def lookup_cross_file_prefixes(name : String, file_path : String) : Array(String)?
      regs = @cross_file_scope_regs
      return unless regs
      base = configured_base_for(file_path)
      matched = [] of String
      regs.each do |r|
        next unless r[:base] == base
        next unless ref_leaf(r[:ref]) == name
        matched << r[:prefix] if ref_matches_file?(r[:ref], file_path)
      end
      matched.empty? ? nil : matched.uniq
    end

    # Candidate module names a Rust source file can be referred to by. A
    # plain `foo.rs` is module `foo`; nested app modules are often reached
    # through an alias in the router file (`apps::td_controllers`), so keep
    # parent directory names too (`apps/todo/controllers.rs` → `todo`).
    private def module_hints(path : String) : Array(String)
      base = File.basename(path, ".rs")
      hints = [] of String
      if base == "mod" || base == "lib" || base == "main"
        parent = File.basename(File.dirname(path))
        hints << parent unless parent.empty?
      else
        hints << base
      end
      dir = File.dirname(path)
      3.times do
        parent = File.basename(dir)
        break if parent.empty? || parent == "." || parent == "/"
        hints << parent unless hints.includes?(parent)
        dir = File.dirname(dir)
      end
      hints
    end

    # ── cross-file `.configure(fn)` prefixes ─────────────────────────

    private def configure_active? : Bool
      m = @configure_fn_prefix
      !!(m && !m.empty?)
    end

    # Scan the project for `web::scope("/p").configure(fn)` /
    # `.configure(|cfg| mod::fn(cfg, ...))` and record each configured fn's
    # composed scope prefix(es).
    private def build_configure_fn_prefix : Array(NamedTuple(base: String, ref: String, prefix: String, source_path: String))
      result = [] of NamedTuple(base: String, ref: String, prefix: String, source_path: String)
      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        base = configured_base_for(fpath)
        src = read_file_content(fpath)
        next unless src.includes?(".configure(") && src.includes?("scope(")
        begin
          aliases = project_import_aliases.merge(import_aliases(src))
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            scope_prefixes = collect_scope_prefixes(root, src, test_regions)
            walk_calls(root) do |call|
              next if RustEngine.inside_test_region?(call, test_regions)
              fn = Noir::TreeSitter.field(call, "function")
              next unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
              fld = Noir::TreeSitter.field(fn, "field")
              next unless fld && Noir::TreeSitter.node_text(fld, src) == "configure"
              receiver = Noir::TreeSitter.field(fn, "value")
              next unless receiver
              enc = enclosing_route_prefix(receiver, src, scope_prefixes)
              next unless enc
              prefix = enc[1]
              next if prefix.empty? || prefix == "/"
              args = Noir::TreeSitter.field(call, "arguments")
              next unless args
              first = nil.as(LibTreeSitter::TSNode?)
              Noir::TreeSitter.each_named_child(args) { |a| first ||= a }
              next unless first
              ref = configure_target_ref(first, src, aliases)
              next unless ref
              entry = {base: base, ref: ref, prefix: prefix, source_path: fpath}
              result << entry unless result.includes?(entry)
            end
          end
        rescue e
          logger.debug "actix configure scan error #{fpath}: #{e}"
        end
      end
      result
    end

    # The configured fn ref from a `.configure(arg)` argument: a
    # direct fn reference (`crate::mod::cfg_fn::<T>`) or a closure that calls
    # one (`|cfg| mod::cfg_fn::<T>(cfg, ...)`).
    private def configure_target_ref(arg : LibTreeSitter::TSNode,
                                     source : String,
                                     aliases : Hash(String, String)) : String?
      case Noir::TreeSitter.node_type(arg)
      when "identifier", "scoped_identifier", "generic_function"
        fn_node_ref(arg, source, aliases)
      when "closure_expression"
        body = Noir::TreeSitter.field(arg, "body")
        return unless body
        found = nil.as(String?)
        walk(body) do |c|
          next if found
          next unless Noir::TreeSitter.node_type(c) == "call_expression"
          f = Noir::TreeSitter.field(c, "function")
          found = fn_node_ref(f, source, aliases) if f
        end
        found
      end
    end

    private def fn_node_ref(node : LibTreeSitter::TSNode, source : String, aliases : Hash(String, String)) : String?
      case Noir::TreeSitter.node_type(node)
      when "identifier"
        Noir::TreeSitter.node_text(node, source)
      when "scoped_identifier"
        expand_import_alias(Noir::TreeSitter.node_text(node, source), aliases)
      when "generic_function"
        inner = Noir::TreeSitter.field(node, "function")
        inner ? fn_node_ref(inner, source, aliases) : nil
      end
    end

    private def import_aliases(source : String) : Hash(String, String)
      aliases = {} of String => String
      source.scan(/\buse\s+([^;{}]+?)\s+as\s+([A-Za-z_]\w*)\s*;/) do |m|
        aliases[m[2]] = m[1].strip
      end
      source.scan(/\buse\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)+)\s*;/) do |m|
        ref = m[1].strip
        aliases[ref_leaf(ref)] = ref unless ref.includes?("::*")
      end
      aliases
    end

    private def import_glob_contexts(source : String) : Array(String)
      contexts = [] of String
      source.scan(/([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)::\*/) do |m|
        context = m[1]
        contexts << context unless contexts.includes?(context)
      end
      contexts
    end

    private def project_import_aliases : Hash(String, String)
      if cached = @project_import_aliases
        return cached
      end

      aliases = {} of String => String
      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        read_file_content(fpath).scan(/\bpub\s+use\s+([^;{}]+?)\s+as\s+([A-Za-z_]\w*)\s*;/) do |m|
          aliases[m[2]] = m[1].strip
        end
      end
      @project_import_aliases = aliases
      aliases
    end

    private def expand_import_alias(ref : String, aliases : Hash(String, String)) : String
      parts = ref.split("::")
      if expanded = aliases[parts[0]]?
        ([expanded] + parts[1..]).join("::")
      else
        ref
      end
    end

    private def build_fn_ranges(root : LibTreeSitter::TSNode, source : String) : Array(Tuple(Int32, Int32, String))
      ranges = [] of Tuple(Int32, Int32, String)
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "function_item"
        name_node = Noir::TreeSitter.field(n, "name")
        next unless name_node
        s = LibTreeSitter.ts_node_start_byte(n).to_i
        e = LibTreeSitter.ts_node_end_byte(n).to_i
        ranges << {s, e, Noir::TreeSitter.node_text(name_node, source)}
      end
      ranges
    end

    private def configure_route_paths(route_path : String,
                                      call : LibTreeSitter::TSNode,
                                      fn_ranges : Array(Tuple(Int32, Int32, String))?,
                                      file_path : String) : Array(String)
      prefixes = configure_prefixes_for(call, fn_ranges, file_path)
      return [route_path] if prefixes.nil? || prefixes.empty?
      prefixes.map { |p| scoped_route_path(p, route_path) }
    end

    private def configure_prefixes_for(call : LibTreeSitter::TSNode,
                                       fn_ranges : Array(Tuple(Int32, Int32, String))?,
                                       file_path : String) : Array(String)?
      return unless fn_ranges
      start = LibTreeSitter.ts_node_start_byte(call).to_i
      best : Tuple(Int32, Int32, String)? = nil
      fn_ranges.each do |r|
        next unless start >= r[0] && start < r[1]
        best = r if best.nil? || (r[1] - r[0]) < (best[1] - best[0])
      end
      best ? lookup_configure_prefixes(best[2], file_path) : nil
    end

    private def lookup_configure_prefixes(name : String, file_path : String) : Array(String)?
      regs = @configure_fn_prefix
      return unless regs
      base = configured_base_for(file_path)
      matched = [] of String
      regs.each do |r|
        next unless r[:base] == base
        next unless ref_leaf(r[:ref]) == name
        next unless ref_matches_file?(r[:ref], file_path, r[:source_path])
        matched << r[:prefix] unless matched.includes?(r[:prefix])
      end
      matched.empty? ? nil : matched
    end

    private def ref_leaf(ref : String) : String
      ref.split("::").last
    end

    private def ref_matches_file?(ref : String, file_path : String, source_path : String? = nil) : Bool
      context = ref_context_segments(ref)
      return !!(source_path && File.expand_path(file_path) == File.expand_path(source_path)) if context.empty?
      hints = module_hints(file_path)
      context.any? { |segment| hints.includes?(segment) }
    end

    private def ref_context_segments(ref : String) : Array(String)
      parts = ref.split("::")
      return [] of String if parts.size == 1
      context = parts[0...-1].reject do |segment|
        {"crate", "self", "super", "controllers", "controller", "routes", "route", "handlers", "handler", "api"}.includes?(segment)
      end
      return context unless context.empty?
      [parts[-2]]
    end

    private def function_name(function : LibTreeSitter::TSNode, source : String) : String?
      name = Noir::TreeSitter.field(function, "name")
      name ? Noir::TreeSitter.node_text(name, source) : nil
    end

    # Walks `call_expression` nodes whose receiver chain looks like
    # `<owner>.route(<path_lit>, <verb>().to(<handler>))` (i.e.,
    # `App::new().route(...)`, `scope("/x").route(...)`,
    # `resource("/y").route(...)`) and returns
    # `{path, [verbs], handler_name?}`. Returns `nil` when the shape
    # doesn't match. The enclosing scope/resource prefix is resolved
    # from `scope_prefixes`, which carries the *fully composed* prefix
    # (so nested `scope("/a").service(scope("/b").route(...))` lands at
    # `/a/b/...`).
    private def extract_builder_route(call : LibTreeSitter::TSNode,
                                      source : String,
                                      scope_prefixes : Hash(Int32, String)) : Tuple(String, Array(String), String?)?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "field_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless Noir::TreeSitter.node_text(field, source) == "route"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |c| named << c }
      return if named.empty?

      receiver = Noir::TreeSitter.field(function, "value")

      # Two argument shapes:
      #   1. `.route("/path", verb().to(handler))` — path is
      #      positional[0], verb-call is positional[1].
      #   2. `.route(verb().to(handler))` (resource builder) — path
      #      lives on the parent `resource("/x")` call sitting as the
      #      receiver of this field_expression.
      if named.size == 1
        return unless receiver
        enc = enclosing_route_prefix(receiver, source, scope_prefixes)
        return unless enc
        path_lit = enc[1]
        methods = extract_web_verbs(named[0], source)
        return if methods.empty?
        return {path_lit, methods, verb_handler_name(named[0], source)}
      end

      # actix uses `.route("", ...)` to register at the scope root; an
      # empty string literal has no `string_content` child, so resolve
      # it to "" explicitly rather than dropping the route.
      path_lit = path_arg_text(named[0], source)
      return unless path_lit

      methods = extract_web_verbs(named[1], source)
      return if methods.empty?

      # If the receiver chain contains a `scope("/x")` call, prepend
      # its fully composed prefix to the route path.
      if receiver && (enc = enclosing_route_prefix(receiver, source, scope_prefixes))
        path_lit = scoped_route_path(enc[1], path_lit)
      end

      {path_lit, methods, verb_handler_name(named[1], source)}
    end

    # `web::resource("/p").to(handler)` / `resource("/p").wrap(m).to(handler)`
    # → `{composed_path, handler_name?}` or nil. The `.to` must sit on a
    # `resource(...)` chain (not a `web::get().to(...)` verb expression); the
    # resource path is composed with any enclosing scope prefix.
    private def extract_resource_to(call : LibTreeSitter::TSNode,
                                    source : String,
                                    scope_prefixes : Hash(Int32, String)) : Tuple(String, String?)?
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field && Noir::TreeSitter.node_text(field, source) == "to"
      receiver = Noir::TreeSitter.field(function, "value")
      return unless receiver
      res = find_resource_in_chain(receiver, source)
      return unless res
      res_node, res_path = res
      full = scope_prefixes[node_byte(res_node)]? || res_path
      {full, resource_to_handler(call, source)}
    end

    # Walk a `.to` receiver chain to its base `resource("/p")` call, skipping
    # intermediate `.wrap(...)`/`.guard(...)` decorators. Returns the resource
    # call node + its path string, or nil when the chain bottoms out at a verb
    # constructor (`web::get()`) or anything that isn't a resource.
    private def find_resource_in_chain(node : LibTreeSitter::TSNode, source : String) : Tuple(LibTreeSitter::TSNode, String)?
      cursor = node
      256.times do
        return unless Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        return unless fn
        case Noir::TreeSitter.node_type(fn)
        when "identifier", "scoped_identifier"
          if Noir::TreeSitter.node_text(fn, source).split("::").last == "resource"
            seg = first_string_literal_text(Noir::TreeSitter.field(cursor, "arguments"), source) || ""
            return {cursor, seg}
          end
          return
        when "field_expression"
          inner = Noir::TreeSitter.field(fn, "value")
          return unless inner
          cursor = inner
        else
          return
        end
      end
      nil
    end

    private def resource_to_handler(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      first = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(args) { |c| first ||= c }
      return unless first
      case Noir::TreeSitter.node_type(first)
      when "identifier", "scoped_identifier"
        Noir::TreeSitter.node_text(first, source)
      end
    end

    # Build a map of each `scope(...)`/`resource(...)` call's start byte
    # to its fully composed path prefix, threading the prefix top-down
    # through `.service(...)` arguments. Chains rooted on a non-scope
    # base (`cfg`, `App::new()`, a variable) carry no inherited prefix;
    # chains rooted *directly* at a `scope(...)`/`resource(...)` (a
    # helper that returns a configured `Scope`) are entered too so their
    # own segment seeds the prefix. A nested scope is reached both as a
    # `.service` argument of its parent (composed prefix) and as its own
    # standalone chain root (bare segment); `register_scope_chain` keeps
    # whichever produced the longer prefix, so the composed one wins.
    private def collect_scope_prefixes(root : LibTreeSitter::TSNode,
                                       source : String,
                                       test_regions : Array(Tuple(Int32, Int32))) : Hash(Int32, String)
      map = {} of Int32 => String
      walk_calls(root) do |call|
        next if RustEngine.inside_test_region?(call, test_regions)
        next unless router_chain_root?(call, source)
        register_scope_chain(call, "", map, source)
      end
      map
    end

    # The outermost method of a builder chain we want to enter as a
    # root: `cfg.service(...)`, `App::new().service(...).route(...)`,
    # `.configure(...)`. Anything else is ignored (the config-fn body
    # is walked independently, so we don't follow the reference).
    private def router_chain_root?(call : LibTreeSitter::TSNode, source : String) : Bool
      fn = Noir::TreeSitter.field(call, "function")
      return false unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
      field = Noir::TreeSitter.field(fn, "field")
      return false unless field
      name = Noir::TreeSitter.node_text(field, source)
      name == "service" || name == "route" || name == "configure"
    end

    # Record this chain's scope/resource prefix and recurse into every
    # `.service(arg)` argument with the composed prefix.
    private def register_scope_chain(expr : LibTreeSitter::TSNode,
                                     inherited : String,
                                     map : Hash(Int32, String),
                                     source : String)
      kind, seg, base_node = resolve_chain_base(expr, source)
      prefix =
        if (kind == :scope || kind == :resource) && seg
          scoped_route_path(inherited, seg)
        else
          inherited
        end
      if (kind == :scope || kind == :resource) && base_node
        key = node_byte(base_node)
        # Longest-prefix-wins: the same scope is registered both as its
        # parent's `.service` argument (fully composed) and as its own
        # standalone chain root (bare segment). Keep the composed one so
        # the standalone walk can't overwrite it with a shorter prefix.
        existing = map[key]?
        map[key] = prefix if existing.nil? || prefix.size > existing.size
      end

      cursor = expr
      256.times do
        break unless Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        break unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
        field = Noir::TreeSitter.field(fn, "field")
        if field && Noir::TreeSitter.node_text(field, source) == "service"
          if sargs = Noir::TreeSitter.field(cursor, "arguments")
            Noir::TreeSitter.each_named_child(sargs) do |arg|
              register_scope_chain(arg, prefix, map, source) if Noir::TreeSitter.node_type(arg) == "call_expression"
            end
          end
        end
        receiver = Noir::TreeSitter.field(fn, "value")
        break unless receiver
        cursor = receiver
      end
    end

    # Walk a builder chain down its receiver spine to the base call and
    # classify it: `{:scope|:resource|:other, path_segment?, base_node}`.
    private def resolve_chain_base(expr : LibTreeSitter::TSNode, source : String) : Tuple(Symbol, String?, LibTreeSitter::TSNode?)
      cursor = expr
      256.times do
        return {:other, nil, nil} unless Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        return {:other, nil, nil} unless fn
        case Noir::TreeSitter.node_type(fn)
        when "field_expression"
          receiver = Noir::TreeSitter.field(fn, "value")
          return {:other, nil, nil} unless receiver
          cursor = receiver
        when "identifier", "scoped_identifier"
          name = Noir::TreeSitter.node_text(fn, source).split("::").last
          case name
          when "scope"
            return {:scope, first_string_literal_text(Noir::TreeSitter.field(cursor, "arguments"), source), cursor}
          when "resource"
            return {:resource, first_string_literal_text(Noir::TreeSitter.field(cursor, "arguments"), source), cursor}
          else
            return {:other, nil, cursor}
          end
        else
          return {:other, nil, nil}
        end
      end
      {:other, nil, nil}
    end

    # Find the nearest enclosing `scope(...)` / `resource(...)` call in a
    # `.route` receiver chain and return its `{kind, full_prefix}`, where
    # `full_prefix` is the composed prefix from `scope_prefixes` (falling
    # back to the call's own path segment for standalone chains not
    # reached via `.service`).
    private def enclosing_route_prefix(receiver : LibTreeSitter::TSNode,
                                       source : String,
                                       scope_prefixes : Hash(Int32, String)) : Tuple(Symbol, String)?
      cursor = receiver
      256.times do
        return unless Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        return unless fn
        case Noir::TreeSitter.node_type(fn)
        when "field_expression"
          inner = Noir::TreeSitter.field(fn, "value")
          return unless inner
          cursor = inner
        when "identifier", "scoped_identifier"
          name = Noir::TreeSitter.node_text(fn, source).split("::").last
          if name == "scope" || name == "resource"
            seg = first_string_literal_text(Noir::TreeSitter.field(cursor, "arguments"), source)
            full = scope_prefixes[node_byte(cursor)]? || seg
            return unless full
            return {name == "scope" ? :scope : :resource, full}
          end
          return
        else
          return
        end
      end
      nil
    end

    # The `.to(handler)` / `.to(handler).method(...)` handler name from a
    # `<verb>().to(handler)` expression, for callee enrichment.
    private def verb_handler_name(node : LibTreeSitter::TSNode, source : String) : String?
      found : String? = nil
      walk(node) do |call|
        next if found
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn = Noir::TreeSitter.field(call, "function")
        next unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
        field = Noir::TreeSitter.field(fn, "field")
        next unless field && Noir::TreeSitter.node_text(field, source) == "to"
        cargs = Noir::TreeSitter.field(call, "arguments")
        next unless cargs
        Noir::TreeSitter.each_named_child(cargs) do |arg|
          case Noir::TreeSitter.node_type(arg)
          when "identifier", "scoped_identifier"
            found = Noir::TreeSitter.node_text(arg, source)
          when "generic_function"
            inner = Noir::TreeSitter.field(arg, "function")
            found = Noir::TreeSitter.node_text(inner, source) if inner
          end
          break if found
        end
      end
      found
    end

    private def node_byte(node : LibTreeSitter::TSNode) : Int32
      LibTreeSitter.ts_node_start_byte(node).to_i
    end

    private def build_function_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      index = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name_node = Noir::TreeSitter.field(node, "name")
        next unless name_node
        name = Noir::TreeSitter.node_text(name_node, source)
        index[name] = node unless index.has_key?(name)
      end
      index
    end

    private def attach_builder_handler_context(endpoint : Endpoint,
                                               handler_name : String,
                                               function_index : Hash(String, LibTreeSitter::TSNode),
                                               source : String,
                                               path : String,
                                               include_callee : Bool)
      leaf = handler_name.split("::").last
      if fn = function_index[leaf]?
        extract_function_params(fn, source, endpoint)
        attach_handler_callees(fn, source, path, endpoint) if include_callee
        return
      end

      entry = lookup_global_function(handler_name)
      return unless entry
      extract_function_params_from_text(entry[:params_text], endpoint)
      attach_rust_callees(endpoint, entry[:callees]) if include_callee
    end

    private def lookup_global_function(ref : String)
      return if ref_context_segments(ref).empty?
      leaf = ref_leaf(ref)
      global_function_index.find do |entry|
        entry[:name] == leaf && ref_matches_function_entry?(ref, entry)
      end
    end

    private def ref_matches_function_entry?(ref : String, entry) : Bool
      context = ref_context_segments(ref)
      return false if context.empty?
      context.any? { |segment| entry[:hints].includes?(segment) }
    end

    private def global_function_index
      if cached = @global_function_index
        return cached
      end

      entries = [] of GlobalFunctionEntry
      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        src = read_file_content(fpath)
        begin
          Noir::TreeSitter.parse_rust(src) do |root|
            walk(root) do |node|
              next unless Noir::TreeSitter.node_type(node) == "function_item"
              name_node = Noir::TreeSitter.field(node, "name")
              next unless name_node
              body = Noir::TreeSitter.field(node, "body")
              params = Noir::TreeSitter.field(node, "parameters")
              callees = if callees_needed? && body
                          Noir::RustCalleeExtractorTS.callees_in_body(body, src, fpath)
                        else
                          [] of Noir::RustCalleeExtractor::Entry
                        end
              entries << {
                name:        Noir::TreeSitter.node_text(name_node, src),
                path:        fpath,
                hints:       module_hints(fpath),
                params_text: params ? Noir::TreeSitter.node_text(params, src) : nil,
                callees:     callees,
              }
            end
          end
        rescue e
          logger.debug "actix global function scan error #{fpath}: #{e}"
        end
      end
      @global_function_index = entries
      entries
    end

    # Normalise actix path-param syntax for the emitted URL:
    #   `{id:\d+}`  -> `{id}`   (typed / regex constraint)
    #   `{tail:.*}` -> `{tail}`
    #   `{rest}*`   -> `{rest}` (tail-match suffix)
    private def canonicalize_actix_path(route : String) : String
      route.gsub(/\{([^{}:]+)(?::[^{}]*)?\}\*?/) { "{#{$~[1].strip}}" }
    end

    # Walks the receiver chain looking for the nearest enclosing
    # `web::scope("/x")` call and returns its path argument.
    private def extract_scope_prefix(node : LibTreeSitter::TSNode, source : String) : String?
      cursor = node
      while Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        return unless fn
        case Noir::TreeSitter.node_type(fn)
        when "scoped_identifier", "identifier"
          # `web::scope("/x")` (scoped) or bare `scope("/x")` from a
          # glob / selective import (`use actix_web::web::*` or
          # `use actix_web::web::scope`).
          name = Noir::TreeSitter.node_text(fn, source).split("::").last
          if name == "scope"
            args = Noir::TreeSitter.field(cursor, "arguments")
            return unless args
            named = [] of LibTreeSitter::TSNode
            Noir::TreeSitter.each_named_child(args) { |c| named << c }
            return if named.empty?
            return first_string_literal_text(named[0], source)
          end
          return
        when "field_expression"
          inner = Noir::TreeSitter.field(fn, "value")
          return unless inner
          cursor = inner
        else
          return
        end
      end
      nil
    end

    private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      field = Noir::TreeSitter.field(function, "field")
      field ? Noir::TreeSitter.node_text(field, source) : nil
    end

    private def named_children(node : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named
    end

    private def scoped_route_path(prefix : String, route_path : String) : String
      normalized_prefix = prefix.starts_with?("/") ? prefix : "/#{prefix}"
      normalized_path = route_path.starts_with?("/") ? route_path : "/#{route_path}"

      return normalized_path if normalized_prefix == "/"
      clean_prefix = normalized_prefix.rstrip('/')
      return normalized_path if normalized_path == clean_prefix || normalized_path.starts_with?("#{clean_prefix}/")

      suffix = normalized_path.lstrip('/')
      return clean_prefix if suffix.empty?

      "#{clean_prefix}/#{suffix}"
    end

    # Pulls every `web::<verb>()` call from a chain like
    # `web::get().to(handler)` or
    # `web::get().or(web::post()).to(handler)`. Walks downward
    # through `call_expression` / `field_expression` until exhausted.
    private def extract_web_verbs(node : LibTreeSitter::TSNode, source : String) : Array(String)
      verbs = [] of String
      walk_calls(node) do |call|
        function = Noir::TreeSitter.field(call, "function")
        next unless function
        case Noir::TreeSitter.node_type(function)
        when "scoped_identifier"
          # `web::get()` is a `call_expression` whose function is a
          # `scoped_identifier` ending in a verb.
          text = Noir::TreeSitter.node_text(function, source)
          if (last = text.split("::").last?) && HTTP_VERBS.includes?(last)
            verbs << last.upcase
          end
        when "identifier"
          # Bare `get()` / `post()` — actix re-exports the route
          # constructors under `web::`, so a glob import
          # (`use actix_web::web::*;`) makes them unqualified
          # identifiers. We only reach here through a `.route(...)`
          # verb-expression argument, so a bare verb name is
          # unambiguously a route constructor (not `map.get(k)`, which
          # is a method call / `field_expression`).
          text = Noir::TreeSitter.node_text(function, source)
          verbs << text.upcase if HTTP_VERBS.includes?(text)
        end
      end
      verbs.uniq
    end

    private def walk_calls(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node) if Noir::TreeSitter.node_type(node) == "call_expression"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_calls(child, &block)
      end
    end

    # `#[get("/x")]` → `{"/x", ["GET"], attr_row_1based}`. The generic
    # `#[route("/x", method = "GET", method = "POST")]` form yields one
    # entry per declared method. Returns `nil` for non-routing
    # attributes (`#[derive(...)]`, `#[tokio::main]`, …) so the iterator
    # just skips past them.
    private def extract_route(attr_item : LibTreeSitter::TSNode,
                              source : String) : Tuple(String, Array(String), Int32)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr

      # tree-sitter-rust models the attribute path as the attribute's
      # required positional named child (identifier / scoped_identifier
      # / self / super / crate / metavariable). There is no `path:`
      # field — the named fields are `arguments` (the `(...)` token
      # tree) and `value` (for `#[key = expr]` shapes).
      name = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          name = Noir::TreeSitter.node_text(child, source).split("::").last.downcase
          break
        end
      end
      return unless name

      arguments = Noir::TreeSitter.field(attr, "arguments")
      route_path = first_string_literal_text(arguments, source)
      return unless route_path
      row = Noir::TreeSitter.node_start_row(attr_item) + 1

      if HTTP_VERBS.includes?(name)
        return {route_path, [name.upcase], row}
      end

      # Generic `#[route("/p", method = "GET", method = "POST")]` /
      # `#[actix_web::route(...)]`: collect each `method = "VERB"`.
      if name == "route"
        methods = extract_route_macro_methods(arguments, source)
        return if methods.empty?
        return {route_path, methods, row}
      end
    end

    # Walk a `#[route("/p", method = "GET", method = "POST")]` argument
    # token tree, collecting every value that follows a `method` key.
    private def extract_route_macro_methods(arguments : LibTreeSitter::TSNode?, source : String) : Array(String)
      methods = [] of String
      return methods unless arguments
      saw_method = false
      walk_calls_all(arguments) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          saw_method = Noir::TreeSitter.node_text(child, source) == "method"
        when "string_literal"
          if saw_method
            if v = string_content_of(child, source)
              methods << v.upcase
            end
            saw_method = false
          end
        end
      end
      methods.uniq
    end

    # Full text of a string literal, concatenating every
    # `string_content` and `escape_sequence` child. tree-sitter-rust
    # splits a literal at each escape (`"/page-{id:\d+}"` → content
    # `/page-{id:`, escape `\d`, content `+}`), so reading only the
    # first `string_content` truncates paths that carry an escape (e.g.
    # a regex-constrained param). Returns nil for a literal with no
    # content children (genuinely empty `""`).
    private def string_content_of(string_literal : LibTreeSitter::TSNode, source : String) : String?
      parts = [] of String
      Noir::TreeSitter.each_named_child(string_literal) do |grand|
        case Noir::TreeSitter.node_type(grand)
        when "string_content", "escape_sequence"
          parts << Noir::TreeSitter.node_text(grand, source)
        end
      end
      parts.empty? ? nil : parts.join
    end

    # The route-path argument of a `.route(path, ...)` call. A bare
    # string literal yields its content, an empty literal `""` yields
    # "" (actix's "register at the scope root" form), and anything that
    # isn't a string literal yields nil so the route is skipped.
    private def path_arg_text(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "string_literal"
      string_content_of(node, source) || ""
    end

    # Walk every node (named children, any depth) and yield each.
    private def walk_calls_all(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_calls_all(child, &block)
      end
    end

    # Path params like `/users/{id}`, the typed/regex `/users/{id:\d+}`
    # form, and the tail-match `/files/{path:.*}` form — all normalise
    # to the bare param name.
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/\{([A-Za-z_]\w*)(?::[^{}]*)?\}/) do |match|
        name = match[1]
        endpoint.push_param(Param.new(name, "", "path")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "path" }
      end
    end

    # Walk the function's `parameters` once and tag the endpoint with
    # whichever extractor types appear. Each parameter's *text* is
    # examined as a single slice — equivalent to the per-line scan in
    # the legacy analyzer, bounded to the parameter list and free of
    # comment / string-literal false positives.
    def extract_function_params(function : LibTreeSitter::TSNode,
                                source : String,
                                endpoint : Endpoint)
      params_node = Noir::TreeSitter.field(function, "parameters")
      if params_node
        Noir::TreeSitter.each_named_child(params_node) do |param|
          extract_function_param_text(Noir::TreeSitter.node_text(param, source), endpoint)
        end
      end

      body_node = Noir::TreeSitter.field(function, "body")
      return unless body_node
      collect_header_and_cookie_params(body_node, source, endpoint)
    end

    private def extract_function_params_from_text(params_text : String?, endpoint : Endpoint)
      return unless params_text
      params_text.split(',').each do |param_text|
        extract_function_param_text(param_text, endpoint)
      end
    end

    private def extract_function_param_text(text : String, endpoint : Endpoint)
      if text.includes?("web::Query<") || text.includes?(": web::Query")
        endpoint.push_param(Param.new("query", "", "query"))
      end
      if text.includes?("web::Json<") || text.includes?(": web::Json")
        endpoint.push_param(Param.new("body", "", "json"))
      end
      if text.includes?("web::Form<") || text.includes?(": web::Form")
        endpoint.push_param(Param.new("form", "", "form"))
      end
    end

    # Scan the body for `req.headers().get("X")` / `req.cookie("X")`
    # — the legacy regex pass, now bounded to `call_expression`
    # function texts so we don't false-positive on comments or string
    # literals containing the same substring.
    private def collect_header_and_cookie_params(body : LibTreeSitter::TSNode,
                                                 source : String,
                                                 endpoint : Endpoint)
      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if fn_text.ends_with?(".headers().get")
          first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source).try do |name|
            endpoint.push_param(Param.new(name, "", "header"))
          end
        elsif fn_text.ends_with?(".cookie")
          first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source).try do |name|
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    private def attach_handler_callees(function : LibTreeSitter::TSNode,
                                       source : String,
                                       path : String,
                                       endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body
      entries = Noir::RustCalleeExtractorTS.callees_in_body(body, source, path)
      attach_rust_callees(endpoint, entries)
    end

    private def call_function_text(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node
      Noir::TreeSitter.node_text(fn_node, source)
    end

    # Walk `node`'s children at every depth and yield `(attribute_item,
    # function_item)` pairs where the attribute immediately precedes
    # the function (skipping intermediate attribute_items and doc
    # comments). This matches how `#[get(...)] async fn handler` is
    # laid out in the AST — both are top-level siblings, not parent /
    # child.
    private def each_routing_pair(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode, LibTreeSitter::TSNode ->)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named.each_with_index do |child, idx|
        if Noir::TreeSitter.node_type(child) == "attribute_item"
          pair_function = find_paired_function(named, idx + 1)
          block.call(child, pair_function) if pair_function
        end
        each_routing_pair(child, &block)
      end
    end

    private def find_paired_function(named : Array(LibTreeSitter::TSNode), start : Int32) : LibTreeSitter::TSNode?
      (start...named.size).each do |i|
        next_node = named[i]
        case Noir::TreeSitter.node_type(next_node)
        when "function_item"
          return next_node
        when "attribute_item", "line_comment", "block_comment"
          next
        else
          return # routing attributes only decorate functions
        end
      end
      nil
    end

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        next unless Noir::TreeSitter.node_type(child) == "string_literal"
        result = string_content_of(child, source)
      end
      result
    end

    private def find_named_child(node : LibTreeSitter::TSNode, type : String) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(node) do |child|
        return child if Noir::TreeSitter.node_type(child) == type
      end
      nil
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
