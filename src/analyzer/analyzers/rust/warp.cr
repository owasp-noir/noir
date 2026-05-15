require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Warp analyzer (tree-sitter port). Warp expresses each endpoint
  # as one `let_declaration` whose value is a chain of filter
  # combinators:
  #
  #     let get_user = warp::path("users")
  #         .and(warp::path::param::<u32>())
  #         .and(warp::path::end())
  #         .and(warp::get())
  #         .map(handler);
  #
  # The analyzer walks every `let_declaration`, inspects its value
  # subtree for the warp::* call shapes, and assembles a single
  # `Endpoint` from them.
  class Warp < RustEngine
    VERB_TO_METHOD = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
    }

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "let_declaration"
          value = Noir::TreeSitter.field(node, "value")
          next unless value
          next unless warp_chain?(value, source)

          endpoint = build_endpoint(value, source, path, Noir::TreeSitter.node_start_row(node) + 1)
          next unless endpoint

          if include_callee
            handler_name = find_handler_name(value, source)
            if handler_name && (handler_fn = function_index[handler_name]?)
              attach_handler_callees(handler_fn, source, path, endpoint)
            end
          end

          endpoints << endpoint
        end
      end

      endpoints
    end

    private def warp_chain?(value : LibTreeSitter::TSNode, source : String) : Bool
      found = false
      walk(value) do |node|
        next if found
        if Noir::TreeSitter.node_type(node) == "scoped_identifier"
          text = Noir::TreeSitter.node_text(node, source)
          found = true if text.starts_with?("warp::")
        end
      end
      found
    end

    # Walk the value subtree once, gathering enough state to build
    # the endpoint: method, ordered path parts, params.
    private def build_endpoint(value : LibTreeSitter::TSNode,
                               source : String,
                               file_path : String,
                               row : Int32) : Endpoint?
      method = "GET"
      path_parts = [] of String
      params = [] of Param
      param_count = 0
      has_path_end = false

      walk(value) do |node|
        case Noir::TreeSitter.node_type(node)
        when "call_expression"
          fn_text = call_function_text(node, source)
          next unless fn_text

          case fn_text
          when "warp::get"     then method = "GET"
          when "warp::post"    then method = "POST"
          when "warp::put"     then method = "PUT"
          when "warp::delete"  then method = "DELETE"
          when "warp::patch"   then method = "PATCH"
          when "warp::head"    then method = "HEAD"
          when "warp::options" then method = "OPTIONS"
          when "warp::path"
            text = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            path_parts << text if text
          when "warp::path::end"
            has_path_end = true
          end
        when "generic_function"
          fn_text = call_function_text_from_generic(node, source)
          next unless fn_text

          if fn_text == "warp::query"
            type_name = first_type_argument(node, source) || "query"
            params << Param.new(type_name, "", "query") unless params.any? { |p| p.name == type_name && p.param_type == "query" }
          elsif fn_text == "warp::body::json" || fn_text == "warp::body::form"
            type_name = first_type_argument(node, source) || "body"
            params << Param.new(type_name, "", "json") unless params.any? { |p| p.name == type_name && p.param_type == "json" }
          end
        when "scoped_identifier"
          text = Noir::TreeSitter.node_text(node, source)
          if text == "warp::path::param"
            param_count += 1
          end
        end
      end

      # Walk again for warp::header(...) / warp::cookie(...) names —
      # the call_expression's function side may be a `generic_function`
      # (turbofish present) or a plain `scoped_identifier`.
      walk(value) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_text = call_function_text(node, source) || call_function_text_from_generic_call(node, source)
        next unless fn_text

        case fn_text
        when "warp::header"
          name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
          params << Param.new(name, "", "header") if name && !params.any? { |p| p.name == name && p.param_type == "header" }
        when "warp::cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
          params << Param.new(name, "", "cookie") if name && !params.any? { |p| p.name == name && p.param_type == "cookie" }
        end
      end

      param_count.times do |i|
        name = param_count > 1 ? "param#{i + 1}" : "param"
        path_parts << ":#{name}"
        params << Param.new(name, "", "path")
      end

      return if path_parts.empty? && !has_path_end

      route = path_parts.empty? ? "/" : "/" + path_parts.join("/")
      details = Details.new(PathInfo.new(file_path, row))
      Endpoint.new(route, method, params, details)
    end

    # `.map(handler)` / `.and_then(handler)` / `.then(handler)` — pull
    # the handler identifier (or trailing segment of a scoped path).
    private def find_handler_name(value : LibTreeSitter::TSNode, source : String) : String?
      found : String? = nil
      walk(value) do |node|
        next if found
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_node = Noir::TreeSitter.field(node, "function")
        next unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
        field = Noir::TreeSitter.field(fn_node, "field")
        next unless field
        method = Noir::TreeSitter.node_text(field, source)
        next unless method == "map" || method == "and_then" || method == "then"

        args = Noir::TreeSitter.field(node, "arguments")
        next unless args
        Noir::TreeSitter.each_named_child(args) do |arg|
          case Noir::TreeSitter.node_type(arg)
          when "identifier"
            found = Noir::TreeSitter.node_text(arg, source)
          when "scoped_identifier"
            found = Noir::TreeSitter.node_text(arg, source).split("::").last
          when "generic_function"
            # `handlers::generic_handler::<u32>` — peel the turbofish.
            inner = Noir::TreeSitter.field(arg, "function")
            if inner
              text = Noir::TreeSitter.node_text(inner, source)
              found = text.split("::").last
            end
          end
          break if found
        end
      end
      found
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
      case Noir::TreeSitter.node_type(fn_node)
      when "scoped_identifier"
        Noir::TreeSitter.node_text(fn_node, source)
      end
    end

    # `foo::<T>` — when a call_expression's function is a
    # `generic_function`, peel one level to find the underlying
    # scoped_identifier / identifier.
    private def call_function_text_from_generic_call(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "generic_function"
      call_function_text_from_generic(fn_node, source)
    end

    private def call_function_text_from_generic(generic : LibTreeSitter::TSNode, source : String) : String?
      inner = Noir::TreeSitter.field(generic, "function")
      return unless inner
      Noir::TreeSitter.node_text(inner, source)
    end

    # `warp::query::<SearchQuery>()` → "SearchQuery". Walks the
    # `type_arguments` field for the first type_identifier and returns
    # its text.
    private def first_type_argument(generic : LibTreeSitter::TSNode, source : String) : String?
      type_args = Noir::TreeSitter.field(generic, "type_arguments")
      return unless type_args
      result : String? = nil
      walk(type_args) do |child|
        next if result
        case Noir::TreeSitter.node_type(child)
        when "type_identifier", "primitive_type"
          result = Noir::TreeSitter.node_text(child, source)
        when "scoped_type_identifier"
          result = Noir::TreeSitter.node_text(child, source).split("::").last
        end
      end
      result
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
