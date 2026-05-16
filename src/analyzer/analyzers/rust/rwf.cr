require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # RWF analyzer (tree-sitter port). RWF wires routes via the
  # `route!("/path" => ControllerName)` macro and resolves the
  # implementation as a `impl Controller for ControllerName` block
  # whose `handle` method's body contains the request handling.
  #
  # The analyzer walks the AST once for both pieces, then joins them:
  #   1. Collect every `impl Controller for X { ... }`'s `handle`
  #      method body into a map keyed by controller name.
  #   2. Walk `macro_invocation` nodes whose macro is `route!` and
  #      extract `(path, controller_name)` from the macro's token
  #      stream.
  #   3. For each route, scan the controller's `handle` body for
  #      `Method::GET` / `Method::POST` etc. to enumerate verbs and
  #      pull params from `request.path_parameter(...)` /
  #      `request.query_parameter(...)` / `request.body()` /
  #      `request.form_data()` / `request.header(...)` /
  #      `request.cookie(...)` shapes.
  class Rwf < RustEngine
    HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      @current_source = source
      Noir::TreeSitter.parse_rust(source) do |root|
        controller_bodies = collect_controller_handle_bodies(root, source)

        # `route!("/path" => Controller)` parses as a top-level
        # `macro_invocation` only when called standalone. When nested
        # inside `vec![ ... ]` (the usual pattern), the lexer leaves
        # `identifier "route"` + `token_tree` as raw tokens of the
        # outer `vec!` macro_invocation's argument. We pick up both
        # shapes by scanning named-children pairs for that signature
        # at every depth.
        each_route_macro(root) do |route_path, controller_name, row|
          body = controller_bodies[controller_name]?
          methods = body ? extract_methods(body, source) : [] of String
          methods << "GET" if methods.empty?

          details = Details.new(PathInfo.new(path, row))
          methods.each do |http_method|
            endpoint = Endpoint.new(route_path, http_method, details)
            extract_path_params(route_path, endpoint)
            if body
              extract_controller_params(body, source, endpoint)
              if include_callee
                entries = Noir::RustCalleeExtractorTS.callees_in_body(body, source, path)
                attach_rust_callees(endpoint, entries)
              end
            end
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    # Yield `(path, controller_name, attr_row_1based)` for every
    # `route!("/path" => Controller)` invocation reachable from
    # `node`. Handles both the top-level `macro_invocation` shape and
    # the more common `vec![route!(...), ...]` nesting, where the
    # `route!(...)` is lexed as raw `identifier "route"` + `token_tree`
    # tokens within the outer macro's token_tree.
    private def each_route_macro(node : LibTreeSitter::TSNode, & : String, String, Int32 ->)
      collect_route_macros(node).each do |route_path, controller, row|
        yield route_path, controller, row
      end
    end

    private def collect_route_macros(node : LibTreeSitter::TSNode) : Array(Tuple(String, String, Int32))
      sink = [] of Tuple(String, String, Int32)
      # Direct macro_invocation form first.
      walk(node) do |child|
        next unless Noir::TreeSitter.node_type(child) == "macro_invocation"
        name_node = Noir::TreeSitter.field(child, "macro")
        next unless name_node
        next unless Noir::TreeSitter.node_text(name_node, @current_source) == "route"
        tokens = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(child) do |c|
          tokens = c if Noir::TreeSitter.node_type(c) == "token_tree"
        end
        next unless tokens_node = tokens
        if route = decode_route_token_tree(tokens_node)
          sink << {route[0], route[1], Noir::TreeSitter.node_start_row(child) + 1}
        end
      end

      # Nested `identifier "route" + token_tree` shape inside larger
      # token_trees (e.g. `vec![route!(...)]`).
      walk_pairs(node) do |a, b|
        next unless Noir::TreeSitter.node_type(a) == "identifier"
        next unless Noir::TreeSitter.node_text(a, @current_source) == "route"
        next unless Noir::TreeSitter.node_type(b) == "token_tree"
        if route = decode_route_token_tree(b)
          sink << {route[0], route[1], Noir::TreeSitter.node_start_row(a) + 1}
        end
      end

      sink
    end

    # Recursively visits each parent's named-children list, calling
    # the block on every adjacent pair. Used to spot the
    # `identifier + token_tree` form of `route!(...)` inside larger
    # macro token_trees.
    private def walk_pairs(node : LibTreeSitter::TSNode, & : LibTreeSitter::TSNode, LibTreeSitter::TSNode ->)
      collect_pairs(node).each { |a, b| yield a, b }
    end

    private def collect_pairs(node : LibTreeSitter::TSNode) : Array(Tuple(LibTreeSitter::TSNode, LibTreeSitter::TSNode))
      pairs = [] of Tuple(LibTreeSitter::TSNode, LibTreeSitter::TSNode)
      collect_pairs_into(node, pairs)
      pairs
    end

    private def collect_pairs_into(node : LibTreeSitter::TSNode,
                                   sink : Array(Tuple(LibTreeSitter::TSNode, LibTreeSitter::TSNode)))
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      (0...named.size - 1).each do |i|
        sink << {named[i], named[i + 1]}
      end
      named.each { |child| collect_pairs_into(child, sink) }
    end

    # The token_tree inside `route!(...)`: walk named children, take
    # the first string_literal as path and the first identifier as
    # controller name.
    private def decode_route_token_tree(tokens : LibTreeSitter::TSNode) : Tuple(String, String)?
      route_path : String? = nil
      controller : String? = nil
      source = @current_source
      Noir::TreeSitter.each_named_child(tokens) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          if route_path.nil?
            Noir::TreeSitter.each_named_child(child) do |grand|
              if Noir::TreeSitter.node_type(grand) == "string_content"
                route_path = Noir::TreeSitter.node_text(grand, source)
                break
              end
            end
          end
        when "identifier"
          controller = Noir::TreeSitter.node_text(child, source) if controller.nil?
        end
      end
      rp = route_path
      ct = controller
      return unless rp && ct
      {rp, ct}
    end

    # Stashed during `analyze_file` so the nested traversal helpers
    # don't need to thread `source` through every recursion.
    @current_source : String = ""

    # Walk all `impl_item` nodes whose trait is `Controller` and store
    # the controller (impl target) → `handle` method's body node.
    private def collect_controller_handle_bodies(root : LibTreeSitter::TSNode,
                                                 source : String) : Hash(String, LibTreeSitter::TSNode)
      result = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "impl_item"
        trait_node = Noir::TreeSitter.field(node, "trait")
        next unless trait_node
        trait_name = Noir::TreeSitter.node_text(trait_node, source).split("::").last
        next unless trait_name == "Controller"

        type_node = Noir::TreeSitter.field(node, "type")
        next unless type_node
        controller_name = Noir::TreeSitter.node_text(type_node, source)

        body_block = Noir::TreeSitter.field(node, "body")
        next unless body_block
        Noir::TreeSitter.each_named_child(body_block) do |member|
          next unless Noir::TreeSitter.node_type(member) == "function_item"
          name_node = Noir::TreeSitter.field(member, "name")
          next unless name_node
          next unless Noir::TreeSitter.node_text(name_node, source) == "handle"
          if handle_body = Noir::TreeSitter.field(member, "body")
            result[controller_name] = handle_body
          end
        end
      end
      result
    end

    # Walk the handle body for `Method::GET` etc. references via
    # `scoped_identifier` nodes. Mirrors the legacy `Method::GET` text
    # scan but only on actual identifier nodes (not comments / strings).
    private def extract_methods(body : LibTreeSitter::TSNode, source : String) : Array(String)
      methods = [] of String
      walk(body) do |node|
        next unless Noir::TreeSitter.node_type(node) == "scoped_identifier"
        text = Noir::TreeSitter.node_text(node, source)
        next unless text.starts_with?("Method::")
        verb = text.sub("Method::", "")
        methods << verb if HTTP_METHODS.includes?(verb) && !methods.includes?(verb)
      end
      methods
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Pull extractor params from `request.<verb>(...)` calls in the
    # body. Recognises both plain (`request.path_parameter("id")`) and
    # turbofish (`request.path_parameter::<i64>("id")`) forms because
    # tree-sitter normalises them to the same `call_expression` shape
    # (the turbofish is a `generic_function` wrapping the field
    # expression).
    private def extract_controller_params(body : LibTreeSitter::TSNode,
                                          source : String,
                                          endpoint : Endpoint)
      existing_path_params = endpoint.params.select { |p| p.param_type == "path" }.map(&.name).to_set

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        method_name = request_method_name(call, source)
        next unless method_name

        case method_name
        when "path_parameter"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !existing_path_params.includes?(name)
            endpoint.push_param(Param.new(name, "", "path"))
          end
        when "query_parameter"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "query" }
            endpoint.push_param(Param.new(name, "", "query"))
          end
        when "body"
          unless endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
        when "form_data"
          unless endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
        when "header"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
          end
        when "cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    # Returns the trailing method name when the call shape is
    # `request.<name>(...)` (with or without turbofish), `nil`
    # otherwise.
    private def request_method_name(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node

      target =
        case Noir::TreeSitter.node_type(fn_node)
        when "field_expression"
          fn_node
        when "generic_function"
          inner = Noir::TreeSitter.field(fn_node, "function")
          inner if inner && Noir::TreeSitter.node_type(inner) == "field_expression"
        end
      return unless target

      receiver = Noir::TreeSitter.field(target, "value")
      return unless receiver && Noir::TreeSitter.node_type(receiver) == "identifier"
      return unless Noir::TreeSitter.node_text(receiver, source) == "request"

      field = Noir::TreeSitter.field(target, "field")
      return unless field
      Noir::TreeSitter.node_text(field, source)
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
