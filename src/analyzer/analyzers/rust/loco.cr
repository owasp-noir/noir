require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Loco analyzer (tree-sitter port). Loco follows Rails conventions:
  # `pub async fn <action>` inside a controller module/impl becomes
  # a RESTful endpoint whose path/method derive from the action name.
  # Loco rides on Axum, so parameter extraction picks up the standard
  # Axum extractor types (`Path<T>`, `Query<T>`, `Json<T>`, `Form<T>`,
  # `HeaderMap`).
  class Loco < RustEngine
    REST_ACTIONS = Set{"index", "show", "new", "create", "edit", "update", "destroy", "delete"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "function_item"
          next unless public_async?(node, source)
          name_node = Noir::TreeSitter.field(node, "name")
          next unless name_node
          action = Noir::TreeSitter.node_text(name_node, source)

          endpoint_path = action_to_path(action, path)
          http_method = infer_http_method(action, node, source)
          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(endpoint_path, http_method, details)

          extract_path_params(endpoint_path, endpoint)
          extract_function_params(node, source, endpoint)
          attach_handler_callees(node, source, path, endpoint) if include_callee

          endpoints << endpoint
        end
      end

      endpoints
    end

    # Loco analysers are scoped to `pub async fn` items only — the
    # legacy regex `pub\s+async\s+fn\s+(\w+)` enforced both modifiers.
    # tree-sitter exposes them as children of the `function_item`'s
    # `visibility_modifier` and `function_modifiers` nodes.
    private def public_async?(function : LibTreeSitter::TSNode, source : String) : Bool
      has_pub = false
      has_async = false
      Noir::TreeSitter.each_named_child(function) do |child|
        case Noir::TreeSitter.node_type(child)
        when "visibility_modifier"
          has_pub = Noir::TreeSitter.node_text(child, source).starts_with?("pub")
        when "function_modifiers"
          has_async = Noir::TreeSitter.node_text(child, source).includes?("async")
        end
      end
      has_pub && has_async
    end

    private def action_to_path(action : String, file_path : String) : String
      controller = controller_name_from_path(file_path)

      case action
      when "index"
        controller.empty? ? "/" : "/#{controller}"
      when "show"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      when "new"
        controller.empty? ? "/new" : "/#{controller}/new"
      when "create"
        controller.empty? ? "/" : "/#{controller}"
      when "edit"
        controller.empty? ? "/:id/edit" : "/#{controller}/:id/edit"
      when "update", "destroy", "delete"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      else
        base_path = controller.empty? ? "" : "/#{controller}"
        "#{base_path}/#{action.gsub(/([A-Z])/, "_\\1").downcase.lstrip("_")}"
      end
    end

    private def controller_name_from_path(file_path : String) : String
      return "" unless file_path.includes?("/controllers/") || file_path.includes?("/controller/")
      file = file_path.split("/").last.gsub(/\.rs$/, "")
      file.gsub(/_controller$/, "")
    end

    private def infer_http_method(action : String, function : LibTreeSitter::TSNode, source : String) : String
      case action
      when "index", "show", "new", "edit"
        "GET"
      when "create", "login", "signup", "register"
        "POST"
      when "update"
        signature_text(function, source).includes?("PUT") ? "PUT" : "PATCH"
      when "destroy", "delete"
        "DELETE"
      else
        sig = signature_text(function, source)
        return "POST" if sig.includes?("Form<")
        return "POST" if sig =~ /\bpost\b/i
        return "PUT" if sig =~ /\bput\b/i
        return "DELETE" if sig =~ /\bdelete\b/i
        return "PATCH" if sig =~ /\bpatch\b/i
        "GET"
      end
    end

    # Function signature minus the body — used by `infer_http_method`
    # so we don't get false hits on `let post = …` style locals.
    private def signature_text(function : LibTreeSitter::TSNode, source : String) : String
      params = Noir::TreeSitter.field(function, "parameters")
      return "" unless params
      return_type = Noir::TreeSitter.field(function, "return_type")
      start_byte = LibTreeSitter.ts_node_start_byte(function).to_i
      end_byte =
        if return_type
          LibTreeSitter.ts_node_end_byte(return_type).to_i
        else
          LibTreeSitter.ts_node_end_byte(params).to_i
        end
      source.byte_slice(start_byte, end_byte - start_byte)
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Loco rides on Axum; extractor types appear in the parameter
    # list. Query / Json / Form get default param names matching the
    # legacy analyzer; Path<T> is already captured from the route
    # pattern.
    private def extract_function_params(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      params = Noir::TreeSitter.field(function, "parameters")
      has_header_map = false
      if params
        Noir::TreeSitter.each_named_child(params) do |param|
          text = Noir::TreeSitter.node_text(param, source)
          if text.includes?("Query<") && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if text.includes?("Json<") && !endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if text.includes?("Form<") && !endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
          has_header_map = true if text.includes?("HeaderMap")
        end
      end

      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if has_header_map && (fn_text.ends_with?(".get") || fn_text == "get")
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && header_name?(name) && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
          end
        elsif fn_text.ends_with?(".cookie") || fn_text == "cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    # The legacy analyzer only kept header-like strings (with a dash
    # or one of the canonical names) to avoid capturing every random
    # `.get("foo")` inside the body.
    private def header_name?(name : String) : Bool
      name.includes?("-") || name.in?(%w[Authorization Content-Type Accept])
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
