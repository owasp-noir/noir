require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Salvo analyzer (tree-sitter port). Salvo wires routes in two
  # shapes, both handled here:
  #
  #   1. Router-chain DSL:
  #        Router::with_path("users/<id>").get(get_user)
  #      Each `.with_path(...)` / `.path(...)` is paired with the
  #      following `.<verb>(handler)` method in the same chain.
  #
  #   2. Attribute macro:
  #        #[endpoint(method = Post, path = "/api/submit/<id>")]
  #        async fn submit_form(...) { ... }
  class Salvo < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          chain = decode_router_chain(node, source)
          next unless chain
          route_path, method, handler_name = chain

          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new("/#{route_path.lstrip('/')}", method, details)
          extract_path_params(route_path, endpoint)

          if handler_function = function_index[handler_name]?
            extract_function_params(handler_function, source, endpoint)
            attach_handler_callees(handler_function, source, path, endpoint) if include_callee
          end

          endpoints << endpoint
        end

        each_routing_pair(root) do |attr_item, function|
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
      end

      endpoints
    end

    # `<chain>.with_path("x").get(handler)` — tree-sitter sees each
    # method call as its own `call_expression { function:
    # field_expression { field: "get", value: call_expression {
    # function: field_expression { field: "with_path", … } } } }`.
    # When the outer call's verb is an HTTP verb AND the receiver is a
    # `.with_path(...)` / `.path(...)` call, we have a complete chain.
    private def decode_router_chain(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String, String)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      verb_field = Noir::TreeSitter.field(fn_node, "field")
      return unless verb_field
      verb = Noir::TreeSitter.node_text(verb_field, source).downcase
      return unless HTTP_VERBS.includes?(verb)

      receiver = Noir::TreeSitter.field(fn_node, "value")
      return unless receiver && Noir::TreeSitter.node_type(receiver) == "call_expression"
      receiver_fn = Noir::TreeSitter.field(receiver, "function")
      return unless receiver_fn
      # `with_path(...)` shows up as both a chain method
      # (`field_expression` with `field: "with_path"`) and a path
      # constructor (`scoped_identifier` like `Router::with_path`).
      # Accept either shape and key off the trailing segment.
      receiver_name =
        case Noir::TreeSitter.node_type(receiver_fn)
        when "field_expression"
          (field = Noir::TreeSitter.field(receiver_fn, "field")) ? Noir::TreeSitter.node_text(field, source) : ""
        when "scoped_identifier"
          Noir::TreeSitter.node_text(receiver_fn, source).split("::").last
        else
          ""
        end
      return unless receiver_name == "with_path" || receiver_name == "path"

      route_path = first_string_literal_text(Noir::TreeSitter.field(receiver, "arguments"), source)
      return unless route_path

      handler_name = first_identifier_argument(call, source)
      return unless handler_name
      {route_path, verb.upcase, handler_name}
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

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/<(\w+)>/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
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
          if fn_text == "req.query" && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if fn_text == "req.header" || fn_text.ends_with?("req.headers().get")
            if name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
              endpoint.push_param(Param.new(name, "", "header")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            end
          end
          if fn_text == "req.cookie"
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

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
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
