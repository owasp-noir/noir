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
      include_callee = any_to_bool(@options["include_callee"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        var_paths = collect_route_variables(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          route = decode_route(node, source, var_paths)
          next unless route
          route_path, method, handler_arg = route

          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(route_path, method, details)
          extract_path_params(route_path, endpoint)

          if handler_arg
            apply_handler(handler_arg, function_index, source, path, endpoint, include_callee)
          end

          endpoints << endpoint
        end
      end

      endpoints
    end

    # Returns `{path, METHOD, handler_arg_node}` for a valid routing
    # call (either chain form or var.verb form), or `nil`.
    private def decode_route(call : LibTreeSitter::TSNode,
                             source : String,
                             var_paths : Hash(String, String)) : Tuple(String, String, LibTreeSitter::TSNode?)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field
      verb = Noir::TreeSitter.node_text(field, source).downcase
      return unless HTTP_VERBS.includes?(verb)

      receiver = Noir::TreeSitter.field(fn_node, "value")
      return unless receiver

      route_path = nil.as(String?)
      case Noir::TreeSitter.node_type(receiver)
      when "call_expression"
        # `app.at("/path").<verb>(handler)` — receiver is the `.at(...)`
        # call.
        receiver_fn = Noir::TreeSitter.field(receiver, "function")
        if receiver_fn && Noir::TreeSitter.node_type(receiver_fn) == "field_expression"
          receiver_field = Noir::TreeSitter.field(receiver_fn, "field")
          if receiver_field && Noir::TreeSitter.node_text(receiver_field, source) == "at"
            route_path = first_string_literal_text(Noir::TreeSitter.field(receiver, "arguments"), source)
          end
        end
      when "identifier"
        var_name = Noir::TreeSitter.node_text(receiver, source)
        route_path = var_paths[var_name]?
      end

      return unless route_path

      handler_arg = first_named_argument(call)
      {route_path, verb.upcase, handler_arg}
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
