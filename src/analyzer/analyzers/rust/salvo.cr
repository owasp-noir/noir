require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Salvo analyzer (tree-sitter port). Salvo wires routes in two
  # shapes, both handled here:
  #
  #   1. Router-chain DSL:
  #        Router::with_path("users/<id>").get(get_user)
  #        Router::new().path("users").hoop(auth).get(list).post(create)
  #      Each `.<verb>(handler)` is paired with the nearest enclosing
  #      `.with_path(...)` / `.path(...)` found by walking up its
  #      receiver chain — so middleware (`.hoop(...)`) and verb chaining
  #      (`.get(a).post(b)`) between the path and the verb don't break
  #      detection.
  #
  #   2. Attribute macro:
  #        #[endpoint(method = Post, path = "/api/submit/<id>")]
  #        async fn submit_form(...) { ... }
  #
  # Router chains are frequently assembled inside a `vec![ ... ]` macro
  # (`impl Routers { fn build() -> Vec<Router> { vec![Router::new()…] } }`).
  # tree-sitter leaves a macro body as a flat `token_tree` with no
  # `call_expression` nodes, so those routes are invisible to a plain
  # AST walk. We recover them by re-parsing each router-bearing macro
  # body as an expression fragment and mapping line numbers back.
  class Salvo < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}
    alias ScopedNameKey = Tuple(String, String)
    alias PrefixEdge = Tuple(ScopedNameKey, String)

    # Cross-function router composition. Salvo apps build their tree with
    # builder fns mounted via `.push(build_system_route())`, where
    # `build_system_route()` lives in another file and returns a nested
    # `Router`. The per-file pass computes each builder's routes relative to
    # that fn's own root, so they lose the prefix the fn is mounted under
    # (`/system/...` instead of `/api/system/...`). `analyze` walks the
    # project once to resolve each builder fn's external mount prefix(es) —
    # following `.push`/`.unshift(child_fn())` edges from the root assembly —
    # and `analyze_file` prepends that prefix to every route emitted inside
    # the fn's body.
    @fn_external_prefix : Hash(ScopedNameKey, Array(String))? = nil
    # Project-wide `const NAME: &str = "..."` values, so a path built by
    # string concatenation (`Router::with_path(PREFIX.to_owned() + "user")`,
    # PREFIX defined in another module) resolves to its real prefix instead
    # of dropping the constant and emitting just `/user`.
    @str_consts : Hash(ScopedNameKey, String)? = nil
    # Cross-file handler params + callees: salvo apps register routes in
    # `routes/x.rs` (`.get(add_user)`) while the `#[handler] fn add_user`
    # lives in `handler/x.rs`. The per-file function index can't see those, so
    # such endpoints surfaced with zero params/callees. Built only when callee
    # enrichment is requested (the ai-context path), keyed by handler name.
    @global_handler_info : Hash(ScopedNameKey, HandlerInfo)? = nil

    record HandlerInfo,
      callees : Array(Noir::RustCalleeExtractor::Entry),
      params : Array(Param)

    def analyze
      @fn_external_prefix = build_fn_external_prefixes
      @str_consts = build_str_consts
      @global_handler_info = callees_needed? ? build_global_handler_info : nil
      super
    end

    # Precompute params + callees for every `#[handler]` fn project-wide so a
    # cross-file `.get(handler)` reference can still be enriched. Gated to
    # files that actually carry a `#[handler]` so plain modules cost nothing.
    private def build_global_handler_info : Hash(ScopedNameKey, HandlerInfo)
      info = {} of ScopedNameKey => HandlerInfo
      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        base = configured_base_for(fpath)
        src = read_file_content(fpath)
        next unless src.includes?("#[handler]")
        begin
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            walk(root) do |n|
              next unless Noir::TreeSitter.node_type(n) == "function_item"
              next if RustEngine.inside_test_region?(n, test_regions)
              name_node = Noir::TreeSitter.field(n, "name")
              next unless name_node
              name = Noir::TreeSitter.node_text(name_node, src)
              key = {base, name}
              next if info.has_key?(key)
              tmp = Endpoint.new("", "")
              extract_function_params(n, src, tmp)
              body = Noir::TreeSitter.field(n, "body")
              callees = body ? Noir::RustCalleeExtractorTS.callees_in_body(body, src, fpath) : [] of Noir::RustCalleeExtractor::Entry
              info[key] = HandlerInfo.new(callees, tmp.params)
            end
          end
        rescue e
          logger.debug "salvo global handler scan error #{fpath}: #{e}"
        end
      end
      info
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      # `crates/core/src/routing.rs`-style `#[cfg(test)] mod tests
      # { Router::with_path(...).get(...) }` blocks would otherwise
      # leak into the endpoint set. See `RustEngine.collect_cfg_test_regions`
      # for the shared helper's rationale.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        # Byte ranges of each fn so a route node can be mapped back to the
        # builder fn that encloses it (for cross-fn external prefixing).
        fn_ranges = build_fn_ranges(root, source)

        # 1. Router chains visible in the real AST.
        collect_chain_endpoints(root, source, source, path, function_index,
          include_callee, 0, test_regions, endpoints, fn_ranges)

        # 2. `#[endpoint(...)]` attribute macros.
        each_routing_pair(root) do |attr_item, function|
          next if RustEngine.inside_test_region?(attr_item, test_regions)
          route = decode_endpoint_macro(attr_item, source)
          next unless route
          route_path, method, attr_row = route

          details = Details.new(PathInfo.new(path, attr_row))
          endpoint = Endpoint.new(route_path, method, details)
          extract_path_params(route_path, endpoint)
          extract_function_params(function, source, endpoint)
          attach_handler_callees(function, source, path, endpoint) if include_callee

          endpoints << endpoint
        end

        # 3. Router chains hidden inside `vec![ ... ]` (and similar)
        # macro bodies. Each fragment is re-parsed with its own
        # source/row offset, but handler functions are still resolved in
        # the real tree's index (handlers live outside the macro).
        collect_router_macro_fragments(root, source, test_regions).each do |fragment, row_offset|
          Noir::TreeSitter.parse_rust(fragment) do |frag_root|
            collect_chain_endpoints(frag_root, fragment, source, path, function_index,
              include_callee, row_offset, nil, endpoints, nil)
          end
        end
      end

      endpoints
    end

    # Walk `chain_root` for `.<verb>(handler)` calls and emit an endpoint
    # for each one whose receiver chain contains a `.with_path(...)` /
    # `.path(...)`. `chain_source` is the text the route nodes belong to
    # (the file, or a re-parsed macro fragment); `original_source` is the
    # file text used for handler-function nodes resolved via the index.
    # `row_offset` maps fragment rows back onto the file.
    private def collect_chain_endpoints(chain_root : LibTreeSitter::TSNode,
                                        chain_source : String,
                                        original_source : String,
                                        path : String,
                                        function_index : Hash(String, LibTreeSitter::TSNode),
                                        include_callee : Bool,
                                        row_offset : Int32,
                                        test_regions : Array(Tuple(Int32, Int32))?,
                                        endpoints : Array(Endpoint),
                                        fn_ranges : Array(Tuple(Int32, Int32, String))?)
      # Nested routers compose their prefix top-down through `.push(...)`:
      # `Router::with_path("api").push(Router::with_path("todos").get(h))`
      # registers GET /api/todos. A flat per-verb receiver-walk only sees
      # the innermost `.path()`, so we first thread the prefix through the
      # push tree and record each Router base node's fully composed prefix.
      router_prefixes = build_router_prefixes(chain_root, chain_source, test_regions, path)

      walk(chain_root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if test_regions && RustEngine.inside_test_region?(node, test_regions)
        chain = decode_router_chain(node, chain_source, router_prefixes, path)
        next unless chain
        route_path, method, handler_name = chain

        row = Noir::TreeSitter.node_start_row(node) + 1 + row_offset

        # If this route sits inside a builder fn mounted cross-file via
        # `.push(builder())`, prepend the fn's external mount prefix(es).
        ext_prefixes = fn_ranges ? external_prefixes_for(node, fn_ranges, path) : nil
        targets = ext_prefixes && !ext_prefixes.empty? ? ext_prefixes : [""]

        targets.each do |ext|
          full_path = ext.empty? ? route_path : join_router_path(ext, route_path)
          details = Details.new(PathInfo.new(path, row))
          endpoint = Endpoint.new("/#{canonicalize_salvo_path(full_path).lstrip('/')}", method, details)
          extract_path_params(full_path, endpoint)

          if handler_name
            leaf = handler_name.split("::").last
            if handler_function = function_index[leaf]?
              extract_function_params(handler_function, original_source, endpoint)
              attach_handler_callees(handler_function, original_source, path, endpoint) if include_callee
            elsif info = @global_handler_info.try(&.[{configured_base_for(path), leaf}]?)
              # The handler lives in another file (`routes/x.rs` references a
              # `#[handler]` in `handler/x.rs`). Its params + callees were
              # precomputed in the cross-file index.
              info.params.each do |p|
                endpoint.push_param(p) unless endpoint.params.any? { |x| x.name == p.name && x.param_type == p.param_type }
              end
              attach_rust_callees(endpoint, info.callees) if include_callee
            end
          end

          endpoints << endpoint
        end
      end
    end

    # `<chain>.<verb>(handler)` → `{path, METHOD, handler_name?}` or
    # `nil`. The verb method is an HTTP verb and the receiver chain must
    # carry a `.with_path(...)` / `.path(...)`. The handler may be a
    # scoped path (`html::pages::login`) or absent (`get(StaticDir::…)`);
    # either way the route is still emitted — the handler is only used to
    # enrich params/callees.
    private def decode_router_chain(call : LibTreeSitter::TSNode,
                                    source : String,
                                    router_prefixes : Hash(Int32, String),
                                    file_path : String) : Tuple(String, String, String?)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      verb_field = Noir::TreeSitter.field(fn_node, "field")
      return unless verb_field
      verb = Noir::TreeSitter.node_text(verb_field, source).downcase
      return unless HTTP_VERBS.includes?(verb)

      route_path = find_chain_path(fn_node, source, router_prefixes, configured_base_for(file_path))
      return unless route_path

      handler_name = first_handler_argument(call, source)
      {route_path, verb.upcase, handler_name}
    end

    # Thread each Router chain's path prefix top-down through `.push(...)`
    # and record `base Router node start-byte -> fully composed prefix`.
    # Roots (chains not reached via `.push`) are processed first thanks to
    # pre-order traversal + a visited set, so every nested chain's prefix
    # is unambiguous.
    private def build_router_prefixes(chain_root : LibTreeSitter::TSNode,
                                      source : String,
                                      test_regions : Array(Tuple(Int32, Int32))?,
                                      file_path : String) : Hash(Int32, String)
      map = {} of Int32 => String
      visited = Set(Int32).new
      base = configured_base_for(file_path)
      walk(chain_root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if visited.includes?(node_byte(node))
        next if test_regions && RustEngine.inside_test_region?(node, test_regions)
        next unless router_chain_call?(node, source)
        register_router_chain(node, "", map, visited, source, base)
      end
      map
    end

    # A call worth treating as a router-chain top: a `.push/.path/
    # .with_path/.<verb>/.hoop(...)` method call or a `Router::*` base.
    ROUTER_METHODS = Set{"push", "unshift", "path", "with_path", "hoop", "then",
                         "get", "post", "put", "delete", "patch", "head", "options"}

    private def router_chain_call?(node : LibTreeSitter::TSNode, source : String) : Bool
      fn = Noir::TreeSitter.field(node, "function")
      return false unless fn
      case Noir::TreeSitter.node_type(fn)
      when "field_expression"
        field = Noir::TreeSitter.field(fn, "field")
        !!(field && ROUTER_METHODS.includes?(Noir::TreeSitter.node_text(field, source)))
      when "scoped_identifier"
        Noir::TreeSitter.node_text(fn, source).starts_with?("Router::")
      else
        false
      end
    end

    private def register_router_chain(top : LibTreeSitter::TSNode,
                                      inherited : String,
                                      map : Hash(Int32, String),
                                      visited : Set(Int32),
                                      source : String,
                                      base : String)
      base_node = nil.as(LibTreeSitter::TSNode?)
      own_seg = nil.as(String?)
      push_args = [] of LibTreeSitter::TSNode

      cursor = top
      256.times do
        break unless Noir::TreeSitter.node_type(cursor) == "call_expression"
        visited.add(node_byte(cursor))
        fn = Noir::TreeSitter.field(cursor, "function")
        break unless fn
        case Noir::TreeSitter.node_type(fn)
        when "field_expression"
          name = (f = Noir::TreeSitter.field(fn, "field")) ? Noir::TreeSitter.node_text(f, source) : ""
          if (name == "path" || name == "with_path") && own_seg.nil?
            own_seg = chain_path_arg(Noir::TreeSitter.field(cursor, "arguments"), source, base)
          elsif name == "push" || name == "unshift"
            if pargs = Noir::TreeSitter.field(cursor, "arguments")
              Noir::TreeSitter.each_named_child(pargs) do |arg|
                push_args << arg if Noir::TreeSitter.node_type(arg) == "call_expression"
              end
            end
          end
          receiver = Noir::TreeSitter.field(fn, "value")
          break unless receiver
          cursor = receiver
        when "scoped_identifier"
          base_node = cursor
          name = Noir::TreeSitter.node_text(fn, source).split("::").last
          if name == "with_path" && own_seg.nil?
            own_seg = chain_path_arg(Noir::TreeSitter.field(cursor, "arguments"), source, base)
          end
          break
        else
          break
        end
      end

      full = own_seg ? join_router_path(inherited, own_seg) : inherited
      if base_node
        map[node_byte(base_node)] = full
      end
      push_args.each { |arg| register_router_chain(arg, full, map, visited, source, base) }
    end

    private def join_router_path(prefix : String, seg : String) : String
      return seg.strip('/') if prefix.empty?
      "#{prefix.rstrip('/')}/#{seg.strip('/')}".strip('/')
    end

    private def node_byte(node : LibTreeSitter::TSNode) : Int32
      LibTreeSitter.ts_node_start_byte(node).to_i
    end

    # Walk up the receiver chain from a `.<verb>(...)` field expression to
    # the chain's `Router::*` base, returning the route's fully composed
    # prefix. `router_prefixes` carries the prefix threaded through any
    # enclosing `.push(...)` (so a nested router inherits its parents'
    # path); we fall back to the chain's own local `.with_path`/`.path`
    # segment when the base wasn't reached via a tracked root. A bare
    # `Router::new().get(h)` (no path) resolves to "" — a real root route
    # at `/`. Returns `nil` only when the chain isn't a Router chain
    # (`map.get(k)`, `req.headers().get("X")` are filtered out this way).
    private def find_chain_path(verb_fn : LibTreeSitter::TSNode,
                                source : String,
                                router_prefixes : Hash(Int32, String),
                                base : String) : String?
      receiver = Noir::TreeSitter.field(verb_fn, "value")
      local_seg = nil.as(String?)
      256.times do
        return local_seg unless receiver && Noir::TreeSitter.node_type(receiver) == "call_expression"
        rfn = Noir::TreeSitter.field(receiver, "function")
        return local_seg unless rfn
        case Noir::TreeSitter.node_type(rfn)
        when "field_expression"
          name = (f = Noir::TreeSitter.field(rfn, "field")) ? Noir::TreeSitter.node_text(f, source) : ""
          if (name == "with_path" || name == "path") && local_seg.nil?
            local_seg = chain_path_arg(Noir::TreeSitter.field(receiver, "arguments"), source, base)
          end
          receiver = Noir::TreeSitter.field(rfn, "value")
        when "scoped_identifier"
          # Chain base such as `Router::with_path("…")` or `Router::new()`.
          name = Noir::TreeSitter.node_text(rfn, source).split("::").last
          if (name == "with_path") && local_seg.nil?
            local_seg = chain_path_arg(Noir::TreeSitter.field(receiver, "arguments"), source, base)
          end
          if full = router_prefixes[node_byte(receiver)]?
            return full
          end
          return local_seg if local_seg
          # `Router::new()` / `Router::with_path()` base with no tracked
          # prefix: a path-less root router still registers at `/`.
          return "" if name == "new" || name == "with_path"
          return
        else
          return local_seg
        end
      end
      nil
    end

    # `#[endpoint(method = Post, path = "/x")]`. tree-sitter-rust
    # leaves the macro arguments as a `token_tree`, but the inner
    # tokens are still tagged — we look for the `method` / `path`
    # keywords and pull the following identifier / string literal.
    private def decode_endpoint_macro(attr_item : LibTreeSitter::TSNode,
                                      source : String) : Tuple(String, String, Int32)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr

      attr_name = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          attr_name = Noir::TreeSitter.node_text(child, source)
          break
        end
      end
      return unless attr_name == "endpoint"

      arguments = Noir::TreeSitter.field(attr, "arguments")
      return unless arguments

      method = "GET"
      route_path = "/"
      saw_method = false
      saw_path = false
      Noir::TreeSitter.each_named_child(arguments) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          name = Noir::TreeSitter.node_text(child, source)
          case name
          when "method"
            saw_method = true
          when "path"
            saw_path = true
          else
            method = name.upcase if saw_method
            saw_method = false
          end
        when "string_literal"
          if saw_path
            text = string_content(child, source)
            route_path = text if text
            saw_path = false
          end
        end
      end
      {route_path, method, Noir::TreeSitter.node_start_row(attr_item) + 1}
    end

    # Salvo path params come in two flavours: the legacy angle form
    # (`<id>`) and the modern brace form (`{id}`, `{*rest}`, `{**path}`,
    # and regex-constrained `{id|[0-9]+}`). Strip capture markers and any
    # inline regex constraint so the param name stays clean.
    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/<(\w+)>/) do |match|
        push_path_param(endpoint, match[1])
      end
      route.scan(/\{\**(\w+)(?:\|[^}]*)?\}/) do |match|
        push_path_param(endpoint, match[1])
      end
    end

    # Strip the constraint from salvo brace params for the emitted URL,
    # keeping the bare name: `{id|[0-9]+}` / `{id:guid}` -> `{id}`,
    # `{**rest}` and `<id>` untouched. Uses balanced-brace matching so a
    # nested regex quantifier (`{8}`) inside the constraint doesn't end
    # the placeholder early.
    private def canonicalize_salvo_path(route : String) : String
      return route unless route.includes?('{')
      String.build do |io|
        i = 0
        while i < route.size
          if route[i] == '{'
            depth = 1
            j = i + 1
            while j < route.size && depth > 0
              depth += 1 if route[j] == '{'
              depth -= 1 if route[j] == '}'
              j += 1
            end
            if depth > 0
              # Unbalanced '{' (no matching '}'): emit the rest verbatim rather
              # than dropping the final char / producing an empty `{}`.
              io << route[i..]
              break
            end
            inner = route[(i + 1)...(j - 1)]
            stars = inner.starts_with?("**") ? "**" : inner.starts_with?("*") ? "*" : ""
            name = inner.lstrip('*').split(/[:|]/, 2).first
            io << "{#{stars}#{name}}"
            i = j
          else
            io << route[i]
            i += 1
          end
        end
      end
    end

    private def push_path_param(endpoint : Endpoint, name : String)
      return if endpoint.params.any? { |p| p.name == name && p.param_type == "path" }
      endpoint.push_param(Param.new(name, "", "path"))
    end

    # Walk parameters + body looking for QueryParam / JsonBody /
    # FormBody / req.header / req.cookie shapes. Bounded to the
    # function so unrelated calls in the file don't bleed in.
    private def extract_function_params(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |node|
        text = Noir::TreeSitter.node_text(node, source)
        case Noir::TreeSitter.node_type(node)
        when "let_declaration", "type_identifier", "scoped_type_identifier", "generic_type"
          if text.includes?("QueryParam") && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if text.includes?("JsonBody") && !endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if text.includes?("FormBody") && !endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
        when "call_expression"
          fn_text = call_function_text(node, source)
          next if fn_text.nil?
          # Strip a turbofish so `req.header::<&str>("x")` /
          # `req.parse_json::<T>()` match like their bare forms.
          base = fn_text.gsub(/::<[^>]*>/, "")
          if (base == "req.query" || base.ends_with?(".parse_queries")) && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          # Salvo's request-side body extractors: `req.parse_json::<T>()` /
          # `req.extract::<T>()` (JSON) and `req.parse_form::<T>()` (form).
          if (base.ends_with?(".parse_json") || base.ends_with?(".extract")) && !endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if base.ends_with?(".parse_form") && !endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
          if base == "req.header" || base.ends_with?("req.headers().get")
            if name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
              endpoint.push_param(Param.new(name, "", "header")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            end
          end
          if base == "req.cookie"
            if name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
              endpoint.push_param(Param.new(name, "", "cookie")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            end
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

    # First identifier / scoped-path argument of a call, used as the
    # handler name. `get(create_user)` → `create_user`,
    # `get(html::pages::login)` → `html::pages::login`.
    private def first_handler_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      nil
    end

    # Collect re-parseable expression fragments for every macro body that
    # mentions `Router`, paired with the 0-based row of the macro's
    # `token_tree` so detected routes map back to their real file line.
    private def collect_router_macro_fragments(root : LibTreeSitter::TSNode,
                                               source : String,
                                               test_regions : Array(Tuple(Int32, Int32))) : Array(Tuple(String, Int32))
      fragments = [] of Tuple(String, Int32)
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "macro_invocation"
        next if RustEngine.inside_test_region?(node, test_regions)
        token_tree = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(node) do |child|
          token_tree = child if Noir::TreeSitter.node_type(child) == "token_tree"
        end
        next unless tt = token_tree
        text = Noir::TreeSitter.node_text(tt, source)
        next unless text.includes?("Router")
        # The prefix carries no newline, so the token_tree's text keeps
        # its original relative line layout and `node_start_row(tt)` is
        # the row offset that maps fragment rows onto the file.
        fragments << {"fn __noir_salvo_wf() { let __noir_x = #{text}; }", Noir::TreeSitter.node_start_row(tt)}
      end
      fragments
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

    # ── cross-fn external prefix resolution ───────────────────────────

    # Byte range + name of every fn, for mapping a route node back to the
    # builder fn that encloses it.
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

    # External mount prefix(es) of the innermost builder fn enclosing `node`,
    # or nil when the enclosing fn is a root-level assembly (no prefix).
    private def external_prefixes_for(node : LibTreeSitter::TSNode,
                                      fn_ranges : Array(Tuple(Int32, Int32, String)),
                                      file_path : String) : Array(String)?
      ext = @fn_external_prefix
      return unless ext
      start = LibTreeSitter.ts_node_start_byte(node).to_i
      best : Tuple(Int32, Int32, String)? = nil
      fn_ranges.each do |r|
        next unless start >= r[0] && start < r[1]
        best = r if best.nil? || (r[1] - r[0]) < (best[1] - best[0])
      end
      return unless chosen = best
      prefixes = ext[{configured_base_for(file_path), chosen[2]}]?
      return unless prefixes
      cleaned = prefixes.reject(&.empty?)
      cleaned.empty? ? nil : cleaned
    end

    # Walk every fn project-wide, thread its body's router chains, and record
    # each `.push(builder())` / `.unshift(builder())` edge as
    # `parent_fn -> (child_fn, local_prefix)`. Resolve those into each pushed
    # fn's absolute external prefix(es).
    private def build_fn_external_prefixes : Hash(ScopedNameKey, Array(String))
      edges = Hash(ScopedNameKey, Array(PrefixEdge)).new
      pushed = Set(ScopedNameKey).new
      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        base = configured_base_for(fpath)
        src = read_file_content(fpath)
        next unless src.includes?(".push(") || src.includes?(".unshift(")
        begin
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            collect_fn_edges(root, src, test_regions, base, edges, pushed)
          end
        rescue e
          logger.debug "salvo fn-edge scan error #{fpath}: #{e}"
        end
      end

      ext = Hash(ScopedNameKey, Array(String)).new
      pushed.each { |f| resolve_external(f, edges, pushed, ext, Set(ScopedNameKey).new) }
      ext
    end

    private def collect_fn_edges(root : LibTreeSitter::TSNode, source : String,
                                 test_regions : Array(Tuple(Int32, Int32)),
                                 base : String,
                                 edges : Hash(ScopedNameKey, Array(PrefixEdge)),
                                 pushed : Set(ScopedNameKey))
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "function_item"
        name_node = Noir::TreeSitter.field(n, "name")
        body = Noir::TreeSitter.field(n, "body")
        next unless name_node && body
        fn_name = Noir::TreeSitter.node_text(name_node, source)
        fn_key = {base, fn_name}
        visited = Set(Int32).new
        walk(body) do |c|
          next unless Noir::TreeSitter.node_type(c) == "call_expression"
          next if visited.includes?(node_byte(c))
          next if RustEngine.inside_test_region?(c, test_regions)
          next unless router_chain_call?(c, source)
          register_fn_edges(c, "", visited, source, fn_key, edges, pushed)
        end
      end
    end

    # Like `register_router_chain`, but records cross-fn push edges instead of
    # a node→prefix map: threads the local prefix and, for each pushed arg
    # that is a plain `builder_fn()` call, emits an edge; for pushed Router
    # chains it recurses to thread the prefix deeper.
    private def register_fn_edges(top : LibTreeSitter::TSNode, inherited : String,
                                  visited : Set(Int32), source : String, fn_key : ScopedNameKey,
                                  edges : Hash(ScopedNameKey, Array(PrefixEdge)),
                                  pushed : Set(ScopedNameKey))
      own_seg = nil.as(String?)
      push_args = [] of LibTreeSitter::TSNode
      cursor = top
      256.times do
        break unless Noir::TreeSitter.node_type(cursor) == "call_expression"
        visited.add(node_byte(cursor))
        fn = Noir::TreeSitter.field(cursor, "function")
        break unless fn
        case Noir::TreeSitter.node_type(fn)
        when "field_expression"
          name = (f = Noir::TreeSitter.field(fn, "field")) ? Noir::TreeSitter.node_text(f, source) : ""
          if (name == "path" || name == "with_path") && own_seg.nil?
            own_seg = chain_path_arg(Noir::TreeSitter.field(cursor, "arguments"), source, fn_key[0])
          elsif name == "push" || name == "unshift"
            if pargs = Noir::TreeSitter.field(cursor, "arguments")
              Noir::TreeSitter.each_named_child(pargs) do |arg|
                push_args << arg if Noir::TreeSitter.node_type(arg) == "call_expression"
              end
            end
          end
          receiver = Noir::TreeSitter.field(fn, "value")
          break unless receiver
          cursor = receiver
        when "scoped_identifier"
          if Noir::TreeSitter.node_text(fn, source).split("::").last == "with_path" && own_seg.nil?
            own_seg = chain_path_arg(Noir::TreeSitter.field(cursor, "arguments"), source, fn_key[0])
          end
          break
        else
          break
        end
      end

      full = own_seg ? join_router_path(inherited, own_seg) : inherited
      push_args.each do |arg|
        if child = fn_call_leaf(arg, source)
          child_key = {fn_key[0], child}
          (edges[fn_key] ||= [] of PrefixEdge) << {child_key, full}
          pushed.add(child_key)
        else
          register_fn_edges(arg, full, visited, source, fn_key, edges, pushed)
        end
      end
    end

    # Builder-fn name of a `build_x()` / `module::build_x()` push arg, or nil
    # when the arg is itself a Router chain or any other expression.
    private def fn_call_leaf(call : LibTreeSitter::TSNode, source : String) : String?
      fn = Noir::TreeSitter.field(call, "function")
      return unless fn
      case Noir::TreeSitter.node_type(fn)
      when "identifier"
        Noir::TreeSitter.node_text(fn, source)
      when "scoped_identifier"
        txt = Noir::TreeSitter.node_text(fn, source)
        txt.starts_with?("Router::") ? nil : txt.split("::").last
      end
    end

    # Resolve a pushed fn's absolute external prefix(es) by composing each
    # parent's prefix with the local prefix of the edge. Roots (fns never
    # pushed) contribute the empty prefix. Memoised, cycle-guarded.
    private def resolve_external(name : ScopedNameKey,
                                 edges : Hash(ScopedNameKey, Array(PrefixEdge)),
                                 pushed : Set(ScopedNameKey),
                                 ext : Hash(ScopedNameKey, Array(String)),
                                 stack : Set(ScopedNameKey)) : Array(String)
      if cached = ext[name]?
        return cached
      end
      return [""] unless pushed.includes?(name)
      return [] of String if stack.includes?(name)
      stack.add(name)
      result = [] of String
      edges.each do |parent, lst|
        lst.each do |child, local|
          next unless child == name
          resolve_external(parent, edges, pushed, ext, stack).each do |pe|
            joined = join_router_path(pe, local)
            result << joined unless result.includes?(joined)
          end
        end
      end
      stack.delete(name)
      final = result.empty? ? [""] : result
      ext[name] = final
      final
    end

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
          return
        end
      end
      nil
    end

    # Collect `const NAME: &str = "..."` / `static NAME: &str = "..."` string
    # constants across the project (regex over source; these are simple
    # top-level declarations). Used to resolve concatenated path prefixes.
    private def build_str_consts : Hash(ScopedNameKey, String)
      consts = {} of ScopedNameKey => String
      pattern = /(?:const|static)\s+([A-Z_][A-Z0-9_]*)\s*:\s*&(?:'static\s+)?str\s*=\s*"([^"]*)"/
      all_files.each do |fpath|
        next if File.directory?(fpath)
        next unless File.exists?(fpath) && File.extname(fpath) == ".rs"
        next if RustEngine.test_path?(fpath)
        base = configured_base_for(fpath)
        src = read_file_content(fpath)
        next unless src.includes?(": &") && src.includes?("str")
        src.scan(pattern) do |m|
          key = {base, m[1]}
          consts[key] = m[2] unless consts.has_key?(key)
        end
      end
      consts
    end

    # The path string of a `.path(...)` / `.with_path(...)` argument,
    # resolving string concatenation (`PREFIX.to_owned() + "user"`) and
    # `const`-defined prefixes. Falls back to the first string literal in the
    # subtree for shapes we don't model.
    private def chain_path_arg(args : LibTreeSitter::TSNode?, source : String, base : String) : String?
      return unless args
      first = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(args) { |c| first ||= c }
      (first ? eval_str_expr(first, source, base) : nil) || first_string_literal_text(args, source)
    end

    private def eval_str_expr(node : LibTreeSitter::TSNode, source : String, base : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "string_literal", "raw_string_literal"
        string_content(node, source)
      when "binary_expression"
        l = Noir::TreeSitter.field(node, "left")
        r = Noir::TreeSitter.field(node, "right")
        lv = l ? eval_str_expr(l, source, base) : nil
        rv = r ? eval_str_expr(r, source, base) : nil
        (lv || rv) ? "#{lv}#{rv}" : nil
      when "call_expression"
        fn = Noir::TreeSitter.field(node, "function")
        return unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
        fld = Noir::TreeSitter.field(fn, "field")
        return unless fld && {"to_owned", "to_string", "into", "as_str"}.includes?(Noir::TreeSitter.node_text(fld, source))
        recv = Noir::TreeSitter.field(fn, "value")
        recv ? eval_str_expr(recv, source, base) : nil
      when "identifier"
        @str_consts.try { |consts| consts[{base, Noir::TreeSitter.node_text(node, source)}]? }
      when "scoped_identifier"
        @str_consts.try { |consts| consts[{base, Noir::TreeSitter.node_text(node, source).split("::").last}]? }
      end
    end

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        case Noir::TreeSitter.node_type(child)
        when "string_literal", "raw_string_literal"
          # Salvo regex-constrained params live in raw strings:
          # `Router::with_path(r"delete/{id|[0-9a-fA-F]{8}}")`. Those are
          # `raw_string_literal` nodes, not `string_literal`.
          result = string_content(child, source)
        end
      end
      result
    end

    private def string_content(string_literal : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(string_literal) do |grand|
        return Noir::TreeSitter.node_text(grand, source) if Noir::TreeSitter.node_type(grand) == "string_content"
      end
      nil
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
