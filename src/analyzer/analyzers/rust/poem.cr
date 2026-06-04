require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Poem analyzer (tree-sitter port). Poem registers routes two ways:
  #
  #   1. Route chain: `Route::new().at("/path", get(handler))`. The
  #      second argument to `.at` is a single `call_expression` or a
  #      chain of `.<verb>(handler)` calls — each method registered
  #      this way creates a separate endpoint sharing the same path.
  #
  #   2. poem-openapi macros: `#[oai(path = "/p", method = "get")]`
  #      attached to functions inside an `impl Api { ... }` block.
  class Poem < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # `#[cfg(test)] mod tests { Route::new().at("/x", get(h)); }` blocks
      # would otherwise leak test-only routes; gate like the other Rust
      # analyzers via the shared region scan.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          next if RustEngine.inside_test_region?(node, test_regions)
          at_call = decode_at_call(node, source)
          next unless at_call
          route_path, method_handler_pairs = at_call

          method_handler_pairs.each do |method, handler_name|
            details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
            normalized = normalize_path(route_path)
            endpoint = Endpoint.new(normalized, method, details)
            extract_path_params(route_path, endpoint)

            if handler_function = function_index[handler_name.split("::").last]?
              scan_function(handler_function, source, endpoint)
              attach_handler_callees(handler_function, source, path, endpoint) if include_callee
            end

            endpoints << endpoint
          end
        end

        # poem-openapi handlers live in an `impl Api` block mounted with
        # `Route::new().nest("/api", api_service)` where
        # `api_service = OpenApiService::new(Api, ...)`. Resolve each impl
        # type's nest prefix so `#[oai(path = "/users")]` surfaces at its
        # real `/api/users` URL.
        oai_prefixes = collect_oai_nest_prefixes(root, source)
        impl_ranges = oai_prefixes.empty? ? nil : build_impl_ranges(root, source)

        each_routing_pair(root) do |attr_item, function|
          next if RustEngine.inside_test_region?(attr_item, test_regions)
          route = decode_oai_attribute(attr_item, source)
          next unless route
          route_path, method, attr_row = route

          prefixes = impl_ranges ? enclosing_impl_prefixes(attr_item, impl_ranges, oai_prefixes) : nil
          raw_paths = prefixes && !prefixes.empty? ? prefixes.map { |p| join_nest_path(p, route_path) } : [route_path]

          raw_paths.each do |raw_path|
            details = Details.new(PathInfo.new(path, attr_row))
            normalized = normalize_path(raw_path)
            endpoint = Endpoint.new(normalized, method, details)
            extract_path_params(raw_path, endpoint)
            scan_function(function, source, endpoint)
            attach_handler_callees(function, source, path, endpoint) if include_callee

            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    # `.at("/path", get(h))` or `.at("/path", get(h).post(h2))` —
    # return `{path, [(METHOD, handler_name), ...]}` or `nil`.
    private def decode_at_call(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(Tuple(String, String)))?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field && Noir::TreeSitter.node_text(field, source) == "at"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |c| named << c }
      return if named.size < 2

      route_path = string_content_from_string_literal(named[0], source)
      return unless route_path

      pairs = decode_method_handler_chain(named[1], source)
      # `.at("/p", index)` / `.at("/p", EmbeddedFileEndpoint::new())` /
      # `.at("/p", metrics.exporter())` register an Endpoint directly with
      # no `get(...)` verb wrapper. poem serves these for any method; emit
      # a single GET so the route surfaces. The handler name (if any) is
      # used for callee/param enrichment.
      if pairs.empty?
        handler = bare_endpoint_handler(named[1], source)
        return unless handler
        return {route_path, [{"GET", handler}]}
      end
      {route_path, pairs}
    end

    # The handler name for a verb-less `.at(path, endpoint)` argument:
    # a bare identifier / scoped path, or the trailing segment of an
    # endpoint-producing call / constructor (`x.exporter()` -> "exporter",
    # `EmbeddedFileEndpoint::<F>::new(..)` -> "new"). Returns "" for an
    # endpoint expression with no recoverable name (still a real route).
    private def bare_endpoint_handler(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "identifier", "scoped_identifier"
        Noir::TreeSitter.node_text(node, source)
      when "call_expression", "generic_function", "field_expression"
        ""
      end
    end

    # Walk `.get(h).post(h2)` chains. Each step is a `call_expression`
    # whose function is either an identifier (verb) — for the leaf —
    # or a `field_expression { value: previous_call, field: verb }`.
    private def decode_method_handler_chain(node : LibTreeSitter::TSNode, source : String) : Array(Tuple(String, String))
      pairs = [] of Tuple(String, String)
      current = node
      while Noir::TreeSitter.node_type(current) == "call_expression"
        fn_node = Noir::TreeSitter.field(current, "function")
        break unless fn_node
        verb = nil.as(String?)
        receiver = nil.as(LibTreeSitter::TSNode?)
        case Noir::TreeSitter.node_type(fn_node)
        when "identifier"
          verb = Noir::TreeSitter.node_text(fn_node, source).downcase
        when "field_expression"
          field = Noir::TreeSitter.field(fn_node, "field")
          verb = Noir::TreeSitter.node_text(field, source).downcase if field
          receiver = Noir::TreeSitter.field(fn_node, "value")
        end
        if verb && HTTP_VERBS.includes?(verb)
          if handler = first_identifier_argument(current, source)
            pairs << {verb.upcase, handler}
          end
        end
        break unless receiver
        current = receiver
      end
      pairs.reverse
    end

    # `#[oai(path = "/x", method = "get")]`. The macro args are a
    # `token_tree` whose named children include `identifier` and
    # `string_literal` in source order.
    private def decode_oai_attribute(attr_item : LibTreeSitter::TSNode,
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
      return unless attr_name == "oai"

      arguments = Noir::TreeSitter.field(attr, "arguments")
      return unless arguments

      route_path : String? = nil
      method : String? = nil
      pending = nil.as(String?)
      Noir::TreeSitter.each_named_child(arguments) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          pending = Noir::TreeSitter.node_text(child, source)
        when "string_literal"
          value = string_content(child, source)
          case pending
          when "path"
            route_path = value
          when "method"
            method = value.try(&.upcase)
          end
          pending = nil
        end
      end
      rp = route_path
      mt = method
      return unless rp && mt
      {rp, mt, Noir::TreeSitter.node_start_row(attr_item) + 1}
    end

    # Convert `:param` syntax to `{param}` and ensure leading slash.
    def normalize_path(route : String) : String
      result = route.gsub(/:(\w+)/) { "{#{$~[1]}}" }
      result.starts_with?("/") ? result : "/#{result}"
    end

    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Walk parameters and body for extractor types + header / cookie
    # calls. Bounded to the function so unrelated calls elsewhere in
    # the file don't leak through.
    private def scan_function(function : LibTreeSitter::TSNode,
                              source : String,
                              endpoint : Endpoint)
      params_node = Noir::TreeSitter.field(function, "parameters")
      if params_node
        Noir::TreeSitter.each_named_child(params_node) do |param|
          text = Noir::TreeSitter.node_text(param, source)
          if !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" } &&
             (text.includes?(": Query<") || text.match(/Query\s*\(\s*[^)]+\s*\)/))
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if !endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" } &&
             (text.includes?(": Json<") || text.match(/Json\s*\(\s*[^)]+\s*\)/))
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if !endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" } &&
             (text.includes?(": Form<") || text.match(/Form\s*\(\s*[^)]+\s*\)/))
            endpoint.push_param(Param.new("form", "", "form"))
          end
        end
      end

      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if fn_text.ends_with?(".header") || fn_text == "header"
          # Request-side header reads take exactly one (string) argument:
          # `req.header("X")`. A two-arg call is a ResponseBuilder SETTING
          # a header (`.header(header::LOCATION, "/")`) — the first arg is
          # a const, the second the value — and must not be read as a
          # request param.
          args = Noir::TreeSitter.field(call, "arguments")
          name = single_string_arg(args, source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
          end
        elsif fn_text.ends_with?(".cookie().get") || fn_text == "cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
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

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          return Noir::TreeSitter.node_text(child, source)
        when "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      nil
    end

    private def string_content_from_string_literal(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "string_literal"
      string_content(node, source)
    end

    # The header name from a single-argument header read (`req.header("X")`),
    # or nil when the call has zero or multiple arguments (a multi-arg
    # `.header(name, value)` is a response-builder set, not a request read).
    private def single_string_arg(args : LibTreeSitter::TSNode?, source : String) : String?
      return unless args
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |c| named << c }
      return unless named.size == 1
      return unless Noir::TreeSitter.node_type(named[0]) == "string_literal"
      string_content(named[0], source)
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

    # ── poem-openapi nest prefix composition ─────────────────────────

    # `{impl_type => [nest prefix]}` from `.nest("/api", api_service)` where
    # `api_service` (or an inline `OpenApiService::new(Api, ...)`) wraps the
    # `impl Api` whose `#[oai]` methods we emit. Only `let`s bound to an
    # `OpenApiService::new(...)` map to a struct — `let ui =
    # api_service.swagger_ui()` doesn't, so the swagger UI mounted at `/`
    # never drags the API impl down to the root.
    private def collect_oai_nest_prefixes(root : LibTreeSitter::TSNode, source : String) : Hash(String, Array(String))
      var_struct = {} of String => String
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "let_declaration"
        pat = Noir::TreeSitter.field(n, "pattern")
        val = Noir::TreeSitter.field(n, "value")
        next unless pat && val
        next unless Noir::TreeSitter.node_text(val, source).includes?("OpenApiService::new")
        if st = openapi_service_struct(val, source)
          var_struct[Noir::TreeSitter.node_text(pat, source)] = st
        end
      end

      result = {} of String => Array(String)
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "call_expression"
        fnf = Noir::TreeSitter.field(n, "function")
        next unless fnf && Noir::TreeSitter.node_type(fnf) == "field_expression"
        fld = Noir::TreeSitter.field(fnf, "field")
        next unless fld && Noir::TreeSitter.node_text(fld, source) == "nest"
        args = Noir::TreeSitter.field(n, "arguments")
        next unless args
        named = [] of LibTreeSitter::TSNode
        Noir::TreeSitter.each_named_child(args) { |c| named << c }
        next if named.size < 2
        prefix = string_content_from_string_literal(named[0], source)
        next unless prefix
        st = resolve_nest_struct(named[1], var_struct, source)
        next unless st
        bucket = (result[st] ||= [] of String)
        bucket << prefix unless bucket.includes?(prefix)
      end
      result
    end

    # The struct passed as the first argument of `OpenApiService::new(...)`
    # found anywhere inside `node` (`OpenApiService::new(Api::default(), ...)`
    # -> "Api").
    private def openapi_service_struct(node : LibTreeSitter::TSNode, source : String) : String?
      found = nil.as(String?)
      walk(node) do |c|
        next if found
        next unless Noir::TreeSitter.node_type(c) == "call_expression"
        fn = Noir::TreeSitter.field(c, "function")
        next unless fn && Noir::TreeSitter.node_text(fn, source).split("::").last(2) == ["OpenApiService", "new"]
        args = Noir::TreeSitter.field(c, "arguments")
        next unless args
        first = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(args) { |a| first ||= a }
        found = first ? struct_type_of(first, source) : nil
      end
      found
    end

    private def struct_type_of(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "identifier", "type_identifier"
        Noir::TreeSitter.node_text(node, source)
      when "scoped_identifier", "scoped_type_identifier"
        Noir::TreeSitter.node_text(node, source).split("::").first
      when "call_expression", "generic_function"
        fn = Noir::TreeSitter.field(node, "function")
        fn ? struct_type_of(fn, source) : nil
      end
    end

    private def resolve_nest_struct(arg : LibTreeSitter::TSNode, var_struct : Hash(String, String), source : String) : String?
      if Noir::TreeSitter.node_text(arg, source).includes?("OpenApiService::new")
        return openapi_service_struct(arg, source)
      end
      base = base_identifier(arg, source)
      base ? var_struct[base]? : nil
    end

    private def base_identifier(node : LibTreeSitter::TSNode, source : String) : String?
      cursor = node
      256.times do
        case Noir::TreeSitter.node_type(cursor)
        when "identifier"
          return Noir::TreeSitter.node_text(cursor, source)
        when "field_expression", "call_expression"
          inner = Noir::TreeSitter.field(cursor, Noir::TreeSitter.node_type(cursor) == "call_expression" ? "function" : "value")
          return unless inner
          cursor = inner
        else
          return
        end
      end
      nil
    end

    private def build_impl_ranges(root : LibTreeSitter::TSNode, source : String) : Array(Tuple(Int32, Int32, String))
      ranges = [] of Tuple(Int32, Int32, String)
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "impl_item"
        type_node = Noir::TreeSitter.field(n, "type")
        next unless type_node
        tname = Noir::TreeSitter.node_text(type_node, source).split("<").first.split("::").last
        s = LibTreeSitter.ts_node_start_byte(n).to_i
        e = LibTreeSitter.ts_node_end_byte(n).to_i
        ranges << {s, e, tname}
      end
      ranges
    end

    private def enclosing_impl_prefixes(node : LibTreeSitter::TSNode,
                                        impl_ranges : Array(Tuple(Int32, Int32, String)),
                                        oai_prefixes : Hash(String, Array(String))) : Array(String)?
      start = LibTreeSitter.ts_node_start_byte(node).to_i
      best : Tuple(Int32, Int32, String)? = nil
      impl_ranges.each do |r|
        next unless start >= r[0] && start < r[1]
        best = r if best.nil? || (r[1] - r[0]) < (best[1] - best[0])
      end
      best ? oai_prefixes[best[2]]? : nil
    end

    private def join_nest_path(prefix : String, path : String) : String
      pfx = (prefix.starts_with?("/") ? prefix : "/#{prefix}").rstrip("/")
      return path.starts_with?("/") ? path : "/#{path}" if pfx.empty?
      suffix = path.lstrip("/")
      suffix.empty? ? pfx : "#{pfx}/#{suffix}"
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

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        if Noir::TreeSitter.node_type(child) == "string_literal"
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
