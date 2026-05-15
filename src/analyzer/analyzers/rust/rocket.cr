require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Rocket analyzer (tree-sitter port). Rocket attaches routes via
  # `#[get("/x")]` / `#[post("/x", data = "<body>")]` outer attribute
  # macros. tree-sitter-rust leaves macro argument lists as
  # `token_tree`, but the lexer still tags `string_literal` /
  # `identifier` children inside — we walk those for the route path,
  # the `data = "<...>"` form, query / path angle-bracket params, and
  # `CookieJar` / `headers().get(...)` body uses.
  class Rocket < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        each_routing_pair(root) do |attr, function|
          route = extract_route(attr, source)
          next unless route
          route_path, method, data_param, attr_row = route

          details = Details.new(PathInfo.new(path, attr_row))
          params = extract_params(route_path, data_param)
          endpoint = Endpoint.new(route_path, method, params, details)

          extract_function_extras(function, source, endpoint)
          attach_handler_callees(function, source, path, endpoint) if include_callee

          endpoints << endpoint
        end
      end

      endpoints
    end

    # `#[get("/x")]` / `#[post("/x", data = "<body>")]` →
    # `{route, METHOD, data_var?, attr_row_1based}`. Returns `nil` for
    # non-routing attributes.
    private def extract_route(attr_item : LibTreeSitter::TSNode,
                              source : String) : Tuple(String, String, String?, Int32)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr

      verb = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          verb = Noir::TreeSitter.node_text(child, source).downcase
          break
        end
      end
      return unless verb
      return unless HTTP_VERBS.includes?(verb)

      arguments = Noir::TreeSitter.field(attr, "arguments")
      return unless arguments
      route_path, data_param = parse_token_tree(arguments, source)
      return unless route_path
      {route_path, verb.upcase, data_param, Noir::TreeSitter.node_start_row(attr_item) + 1}
    end

    # Walk the attribute's token_tree once. First `string_literal` is
    # the route path. Any `identifier "data"` followed by a
    # `string_literal` yields the data parameter variable name (the
    # `<input>` form). Other keyword args are ignored — rocket's
    # `format = "..."` / `rank = N` aren't endpoint-shaping.
    private def parse_token_tree(token_tree : LibTreeSitter::TSNode,
                                 source : String) : Tuple(String?, String?)
      route_path : String? = nil
      data_param : String? = nil
      saw_data = false

      Noir::TreeSitter.each_named_child(token_tree) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          text = string_content(child, source)
          if route_path.nil?
            route_path = text
          elsif saw_data && data_param.nil?
            # `data = "<input>"` — strip the angle brackets.
            data_param = strip_angle_brackets(text) if text
            saw_data = false
          end
        when "identifier"
          saw_data = true if Noir::TreeSitter.node_text(child, source) == "data"
        end
      end

      {route_path, data_param}
    end

    private def strip_angle_brackets(value : String?) : String?
      return unless value
      if value.starts_with?('<') && value.ends_with?('>')
        value[1..-2]
      else
        value
      end
    end

    # `/users/<id>` / `/search?<q>&<limit>` / `data = "<body>"` get
    # rolled together here so the legacy spec's param ordering stays
    # stable.
    private def extract_params(route : String, data_param : String?) : Array(Param)
      params = [] of Param

      parts = route.split("?", 2)
      path_part = parts[0]
      query_part = parts[1]?

      path_part.scan(/<(\w+)>/) do |match|
        name = match[1]
        params << Param.new(name, "", "path") unless params.any? { |p| p.name == name && p.param_type == "path" }
      end

      if query_part
        query_part.scan(/<(\w+)>/) do |match|
          name = match[1]
          params << Param.new(name, "", "query") unless params.any? { |p| p.name == name && p.param_type == "query" }
        end
      end

      if data_param && !data_param.empty?
        params << Param.new(data_param, "", "body")
      end

      params
    end

    # Cookies and headers come from the function signature + body.
    # The `CookieJar` signature gate from the legacy analyzer is
    # preserved — `cookies.get(...)` only counts when the function
    # actually takes a `CookieJar`.
    private def extract_function_extras(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      has_cookie_jar = false
      params_node = Noir::TreeSitter.field(function, "parameters")
      if params_node
        Noir::TreeSitter.each_named_child(params_node) do |param|
          has_cookie_jar = true if Noir::TreeSitter.node_text(param, source).includes?("CookieJar")
        end
      end

      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if has_cookie_jar && (fn_text.ends_with?(".get") || fn_text.ends_with?(".get_private"))
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        elsif fn_text.ends_with?(".headers().get")
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
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
