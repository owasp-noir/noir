require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Tide analyzer (tree-sitter port). Tide registers routes in two
  # shapes, both handled here:
  #
  #   1. Direct chain:
  #        app.at("/users/:id").get(get_user);
  #
  #   2. Variable + method:
  #        let health_route = app.at("/health");
  #        health_route.get(health_check);
  #
  # We collect both `let <var> = <expr>.at("/path")` bindings and
  # direct `.at("/path").<verb>(handler)` chains in a single AST pass.
  class Tide < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Inline `#[cfg(test)] mod test { let mut app = tide::new();
      # app.at("/x").get(h); }` blocks live right in `src/` here, so a
      # path filter alone can't tell them apart — gate via the shared scan.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        var_paths = collect_route_variables(root, source)
        nest_ranges = collect_nest_ranges(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          next if RustEngine.inside_test_region?(node, test_regions)
          route = decode_route(node, source, var_paths)
          next unless route
          route_path, method, handler_arg = route
          full_path = apply_nest_prefix(node, route_path, nest_ranges)

          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(full_path, method, details)
          extract_path_params(full_path, endpoint)

          if handler_arg
            apply_handler(handler_arg, function_index, source, path, endpoint, include_callee)
          end

          endpoints << endpoint
        end
      end

      endpoints
    end

    # `serve_dir` / `serve_file` are static-mount terminals that respond
    # to GET, registered the same `app.at("/p").serve_dir("dir")` way.
    STATIC_VERBS = Set{"serve_dir", "serve_file"}

    # Returns `{path, METHOD, handler_arg_node}` for a valid routing
    # call (chain form, multi-verb chain, var.verb form, or a static
    # serve_dir/serve_file mount), or `nil`.
    private def decode_route(call : LibTreeSitter::TSNode,
                             source : String,
                             var_paths : Hash(String, String)) : Tuple(String, String, LibTreeSitter::TSNode?)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field
      name = Noir::TreeSitter.node_text(field, source).downcase
      method =
        if HTTP_VERBS.includes?(name)
          name.upcase
        elsif STATIC_VERBS.includes?(name)
          "GET"
        end
      return unless method

      receiver = Noir::TreeSitter.field(fn_node, "value")
      return unless receiver

      # Walk the receiver chain up through any intermediate verb calls
      # (`app.at("/p").put(h).get(h2)` chains both PUT and GET on /p) to
      # the `.at("path")` call or a route-variable identifier.
      route_path = resolve_at_path(receiver, source, var_paths)
      return unless route_path

      handler_arg = first_named_argument(call)
      {route_path, method, handler_arg}
    end

    # Walk a verb call's receiver chain to the `.at("path")` that defines
    # its path (skipping chained verbs), or resolve a route-variable
    # identifier. Returns the path string or `nil`.
    private def resolve_at_path(node : LibTreeSitter::TSNode,
                                source : String,
                                var_paths : Hash(String, String)) : String?
      cursor = node
      256.times do
        case Noir::TreeSitter.node_type(cursor)
        when "identifier"
          return var_paths[Noir::TreeSitter.node_text(cursor, source)]?
        when "call_expression"
          cfn = Noir::TreeSitter.field(cursor, "function")
          return unless cfn && Noir::TreeSitter.node_type(cfn) == "field_expression"
          cfield = Noir::TreeSitter.field(cfn, "field")
          fname = cfield ? Noir::TreeSitter.node_text(cfield, source) : ""
          if fname == "at"
            return first_string_literal_text(Noir::TreeSitter.field(cursor, "arguments"), source)
          end
          receiver = Noir::TreeSitter.field(cfn, "value")
          return unless receiver
          cursor = receiver
        else
          return
        end
      end
      nil
    end

    # Collect `app.at("/pre").nest(arg)` mounts as `{arg_byte_range,
    # local_prefix}`. Routes whose byte falls inside `arg` inherit the
    # prefix (composed across nested mounts in apply_nest_prefix).
    private def collect_nest_ranges(root : LibTreeSitter::TSNode, source : String) : Array(Tuple(Int32, Int32, String))
      ranges = [] of Tuple(Int32, Int32, String)
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_node = Noir::TreeSitter.field(node, "function")
        next unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
        field = Noir::TreeSitter.field(fn_node, "field")
        next unless field && Noir::TreeSitter.node_text(field, source) == "nest"
        receiver = Noir::TreeSitter.field(fn_node, "value")
        next unless receiver
        prefix = resolve_at_path(receiver, source, {} of String => String)
        next unless prefix
        args = Noir::TreeSitter.field(node, "arguments")
        next unless args
        arg = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(args) { |c| arg ||= c }
        next unless mount = arg
        ranges << {LibTreeSitter.ts_node_start_byte(mount).to_i, LibTreeSitter.ts_node_end_byte(mount).to_i, prefix}
      end
      ranges
    end

    # Prepend every enclosing nest prefix (outermost first) to a route.
    private def apply_nest_prefix(node : LibTreeSitter::TSNode,
                                  route_path : String,
                                  ranges : Array(Tuple(Int32, Int32, String))) : String
      return route_path if ranges.empty?
      b = LibTreeSitter.ts_node_start_byte(node).to_i
      enclosing = ranges.select { |s, e, _| b >= s && b < e }.sort_by! { |s, _, _| s }
      return route_path if enclosing.empty?
      prefix = enclosing.map { |_, _, p| "/#{p.strip('/')}" }.join.rstrip('/')
      "#{prefix}/#{route_path.lstrip('/')}"
    end

    # Walk `let <var> = …` bindings and record `var → path` for
    # bindings whose RHS is a `.at("path")` call somewhere. We use
    # the *outermost* `.at` we find on the RHS, mirroring the legacy
    # `(\w+)\s*=\s*\w+\.at(...)` regex.
    private def collect_route_variables(root : LibTreeSitter::TSNode,
                                        source : String) : Hash(String, String)
      vars = {} of String => String
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "let_declaration"
        pattern = Noir::TreeSitter.field(node, "pattern")
        next unless pattern && Noir::TreeSitter.node_type(pattern) == "identifier"
        name = Noir::TreeSitter.node_text(pattern, source)

        value = Noir::TreeSitter.field(node, "value")
        next unless value
        path = find_at_call_path(value, source)
        vars[name] = path if path
      end
      vars
    end

    private def find_at_call_path(node : LibTreeSitter::TSNode, source : String) : String?
      result : String? = nil
      walk(node) do |child|
        next if result
        next unless Noir::TreeSitter.node_type(child) == "call_expression"
        fn_node = Noir::TreeSitter.field(child, "function")
        next unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
        field = Noir::TreeSitter.field(fn_node, "field")
        next unless field && Noir::TreeSitter.node_text(field, source) == "at"
        result = first_string_literal_text(Noir::TreeSitter.field(child, "arguments"), source)
      end
      result
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # The handler argument is either an identifier (function name we
    # can look up in the file's function index), a closure (no extra
    # param extraction — closures rarely declare `req.query` etc.),
    # or a scoped/generic identifier.
    private def apply_handler(handler_arg : LibTreeSitter::TSNode,
                              function_index : Hash(String, LibTreeSitter::TSNode),
                              source : String,
                              file_path : String,
                              endpoint : Endpoint,
                              include_callee : Bool)
      handler_name =
        case Noir::TreeSitter.node_type(handler_arg)
        when "identifier"
          Noir::TreeSitter.node_text(handler_arg, source)
        when "scoped_identifier"
          Noir::TreeSitter.node_text(handler_arg, source).split("::").last
        when "generic_function"
          inner = Noir::TreeSitter.field(handler_arg, "function")
          inner ? Noir::TreeSitter.node_text(inner, source).split("::").last : nil
        end
      return unless handler_name

      handler_function = function_index[handler_name]?
      return unless handler_function

      scan_function(handler_function, source, endpoint)
      attach_handler_callees(handler_function, source, file_path, endpoint) if include_callee
    end

    # Walk the handler body once, pulling extractor types from
    # `let <ident> : <type> = req.query() / req.body_json() /
    # req.body_form()` shapes, and header / cookie names from
    # `req.header("X")` / `req.cookie("X")` calls.
    private def scan_function(function : LibTreeSitter::TSNode,
                              source : String,
                              endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |node|
        case Noir::TreeSitter.node_type(node)
        when "let_declaration"
          add_typed_extractor(node, source, endpoint)
        when "call_expression"
          add_header_or_cookie(node, source, endpoint)
        end
      end
    end

    # `let user: UserData = req.body_json().await;` — when the RHS
    # eventually calls `req.query()` / `req.body_json()` /
    # `req.body_form()`, the pattern-side type identifier becomes the
    # extractor's param name (matching the legacy `let \w+ : (\w+)`
    # regex).
    private def add_typed_extractor(let_decl : LibTreeSitter::TSNode,
                                    source : String,
                                    endpoint : Endpoint)
      type_node = Noir::TreeSitter.field(let_decl, "type")
      return unless type_node
      value = Noir::TreeSitter.field(let_decl, "value")
      return unless value

      kind = nil.as(String?)
      walk(value) do |child|
        next if kind
        next unless Noir::TreeSitter.node_type(child) == "call_expression"
        fn_text = call_function_text(child, source)
        next unless fn_text
        case fn_text
        when "req.query"     then kind = "query"
        when "req.body_json" then kind = "json"
        when "req.body_form" then kind = "form"
        end
      end
      return unless kind

      type_name = type_name_text(type_node, source)
      return unless type_name
      param_type = kind == "query" ? "query" : kind == "json" ? "json" : "form"
      unless endpoint.params.any? { |p| p.name == type_name && p.param_type == param_type }
        endpoint.push_param(Param.new(type_name, "", param_type))
      end
    end

    private def type_name_text(type_node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(type_node)
      when "type_identifier"
        Noir::TreeSitter.node_text(type_node, source)
      when "scoped_type_identifier"
        Noir::TreeSitter.node_text(type_node, source).split("::").last
      when "generic_type"
        inner = Noir::TreeSitter.field(type_node, "type")
        inner ? type_name_text(inner, source) : nil
      end
    end

    private def add_header_or_cookie(call : LibTreeSitter::TSNode,
                                     source : String,
                                     endpoint : Endpoint)
      fn_text = call_function_text(call, source)
      return unless fn_text

      case fn_text
      when "req.header"
        name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
        if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
          endpoint.push_param(Param.new(name, "", "header"))
        end
      when "req.cookie"
        name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
        if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
          endpoint.push_param(Param.new(name, "", "cookie"))
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

    private def first_named_argument(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        return child
      end
      nil
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

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        if Noir::TreeSitter.node_type(child) == "string_literal"
          Noir::TreeSitter.each_named_child(child) do |grand|
            if Noir::TreeSitter.node_type(grand) == "string_content"
              result = Noir::TreeSitter.node_text(grand, source)
              break
            end
          end
        end
      end
      result
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
