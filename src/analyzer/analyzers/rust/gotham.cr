require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Gotham analyzer (tree-sitter port). Gotham wires routes with a
  # builder chain that pairs each verb call with a following `.to`:
  #
  #     Router::builder()
  #         .get("/users/:id").to(user_handler)
  #         .post("/users").to(create_user_handler)
  #
  # The analyzer walks `call_expression` nodes whose function is a
  # `field_expression` named `to` — the receiver of `.to(handler)` is
  # the `.<verb>("/path")` call, so each routing entry has both
  # pieces locally and we don't need to thread state through the
  # chain.
  class Gotham < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        walk_with_prefix(root, source, "", path, function_index, include_callee, endpoints)
      end

      endpoints
    end

    # Recursive descent that threads the current path prefix. Gotham's
    # `build_router(|route| { ... })` groups routes under
    # `route.scope("/api", |route| { ... })` closures (which prepend a
    # path segment) and `route.with_pipeline_chain(chain, |route| { ... })`
    # closures (which only add middleware). A flat walk reported the
    # inner path verbatim — `/users` instead of `/api/users`. We now
    # descend into each closure carrying the accumulated prefix.
    private def walk_with_prefix(node : LibTreeSitter::TSNode,
                                 source : String,
                                 prefix : String,
                                 path : String,
                                 function_index : Hash(String, LibTreeSitter::TSNode),
                                 include_callee : Bool,
                                 endpoints : Array(Endpoint))
      if Noir::TreeSitter.node_type(node) == "call_expression"
        if scope = decode_scope(node, source)
          seg, block = scope
          walk_with_prefix(block, source, join_paths(prefix, seg), path, function_index, include_callee, endpoints)
          return
        end
        if block = decode_pipeline_closure(node, source)
          walk_with_prefix(block, source, prefix, path, function_index, include_callee, endpoints)
          return
        end
        if route = decode_to_call(node, source)
          route_path, method, handler_name = route
          full_path = join_paths(prefix, route_path)

          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(full_path, method, details)
          extract_path_params(full_path, endpoint)

          if handler_function = function_index[handler_name]?
            scan_function(handler_function, source, endpoint)
            attach_handler_callees(handler_function, source, path, endpoint) if include_callee
          end

          endpoints << endpoint
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_with_prefix(child, source, prefix, path, function_index, include_callee, endpoints)
      end
    end

    # `route.scope("/seg", |route| { ... })` → `{seg, closure_body}`.
    private def decode_scope(call : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field && Noir::TreeSitter.node_text(field, source) == "scope"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      seg = first_string_literal_text(args, source)
      return unless seg
      block = closure_body(args)
      return unless block
      {seg, block}
    end

    # Pipeline-grouping closures (`with_pipeline_chain`, `with_pipeline`)
    # wrap routes with middleware without changing the path. Returns the
    # closure body so the caller can descend with the same prefix.
    private def decode_pipeline_closure(call : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field
      name = Noir::TreeSitter.node_text(field, source)
      return unless name == "with_pipeline_chain" || name == "with_pipeline"
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      closure_body(args)
    end

    # Body block of the first closure argument in an `arguments` node.
    private def closure_body(args : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "closure_expression"
        body = Noir::TreeSitter.field(arg, "body")
        return body if body && Noir::TreeSitter.node_type(body) == "block"
        Noir::TreeSitter.each_named_child(arg) do |child|
          return child if Noir::TreeSitter.node_type(child) == "block"
        end
      end
      nil
    end

    private def join_paths(prefix : String, route_path : String) : String
      return ensure_leading_slash(route_path) if prefix.empty?
      combined = "/#{prefix.strip('/')}/#{route_path.lstrip('/')}".rstrip('/')
      combined.empty? ? "/" : combined
    end

    private def ensure_leading_slash(route_path : String) : String
      route_path.starts_with?("/") ? route_path : "/#{route_path}"
    end

    # `.<verb>("/x").to(handler)` → `{path, METHOD, handler_name}` or
    # `nil`. Reaches up one level: the `.to` call's receiver should
    # itself be a `.<verb>("...")` call.
    private def decode_to_call(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String, String)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field && Noir::TreeSitter.node_text(field, source) == "to"

      receiver = Noir::TreeSitter.field(fn_node, "value")
      return unless receiver && Noir::TreeSitter.node_type(receiver) == "call_expression"

      verb_fn = Noir::TreeSitter.field(receiver, "function")
      return unless verb_fn && Noir::TreeSitter.node_type(verb_fn) == "field_expression"
      verb_field = Noir::TreeSitter.field(verb_fn, "field")
      return unless verb_field
      verb = Noir::TreeSitter.node_text(verb_field, source).downcase
      return unless HTTP_VERBS.includes?(verb)

      route_path = first_string_literal_text(Noir::TreeSitter.field(receiver, "arguments"), source)
      return unless route_path
      handler = first_identifier_argument(call, source)
      return unless handler
      {route_path, verb.upcase, handler}
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Header / cookie / `header::Name` extraction from the handler
    # body. Walks `call_expression` nodes once; `header::FooBar`
    # appears as `scoped_identifier` and is converted to a header name
    # by replacing underscores with hyphens (matches the legacy
    # analyzer's gsub).
    private def scan_function(function : LibTreeSitter::TSNode,
                              source : String,
                              endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |node|
        case Noir::TreeSitter.node_type(node)
        when "call_expression"
          fn_text = call_function_text(node, source)
          next if fn_text.nil?
          if fn_text.ends_with?(".cookie")
            name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
              endpoint.push_param(Param.new(name, "", "cookie"))
            end
          elsif fn_text.ends_with?(".headers().get")
            name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
              endpoint.push_param(Param.new(name, "", "header"))
            end
          end
        when "scoped_identifier"
          text = Noir::TreeSitter.node_text(node, source)
          if text.starts_with?("header::")
            header_name = text.sub("header::", "").gsub("_", "-")
            if !endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
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
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          return Noir::TreeSitter.node_text(child, source)
        when "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source).split("::").last
        end
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
