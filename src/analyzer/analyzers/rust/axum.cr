require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Axum analyzer (tree-sitter port). Each `.rs` file is parsed once
  # with the vendored Rust grammar; route registrations are picked up
  # by walking `call_expression` nodes whose function is a
  # `field_expression` named `route`. Handler bodies are matched
  # against a same-file `function_item` index so callee extraction
  # shares the parsed tree instead of re-scanning the file with
  # regexes and a body-text wrapper.
  class Axum < RustEngine
    # Verbs accepted as the inner handler call (`get(...)`, `post(...)`,
    # …). Anything outside this set is treated as `GET` to match the
    # legacy fallback the regex analyzer used.
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = include_callee ? build_function_index(root, source) : Hash(String, LibTreeSitter::TSNode).new

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          next unless route_call?(node, source)

          route = extract_route(node, source)
          next unless route

          path_str, verb, handler_name = route
          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(path_str, verb, details)

          if include_callee && handler_name && (body_node = function_index[handler_name]?)
            entries = Noir::RustCalleeExtractorTS.callees_in_body(body_node, source, path)
            attach_rust_callees(endpoint, entries)
          end

          endpoints << endpoint
        end
      end

      endpoints
    end

    # `.route("...", get(handler))` — the chain is rooted on
    # `Router::new()` but tree-sitter sees each `.route(...)` as its
    # own `call_expression` because the receiver chain is left-folded.
    private def route_call?(call : LibTreeSitter::TSNode, source : String) : Bool
      fn_node = Noir::TreeSitter.field(call, "function")
      return false unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return false unless field
      Noir::TreeSitter.node_text(field, source) == "route"
    end

    # Returns `{path, http_method, handler_name?}` for a valid
    # `.route(path, verb(handler))` call, or `nil` when the shape
    # doesn't match.
    private def extract_route(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String, String?)?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |c| named << c }
      return if named.size < 2

      path = string_literal_text(named[0], source)
      return unless path

      method, handler = decode_handler(named[1], source)
      {path, method, handler}
    end

    # `get(handler)` → `{"GET", "handler"}`. Defaults to `GET` when
    # the verb is unrecognised, matching the legacy fallback.
    private def decode_handler(node : LibTreeSitter::TSNode, source : String) : Tuple(String, String?)
      if Noir::TreeSitter.node_type(node) == "call_expression"
        fn_node = Noir::TreeSitter.field(node, "function")
        if fn_node && Noir::TreeSitter.node_type(fn_node) == "identifier"
          verb = Noir::TreeSitter.node_text(fn_node, source).downcase
          method = HTTP_VERBS.includes?(verb) ? verb.upcase : "GET"
          handler = first_identifier_argument(node, source)
          return {method, handler}
        end
      end
      {"GET", nil}
    end

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
      end
      nil
    end

    private def string_literal_text(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "string_literal"
      content = nil.as(String?)
      Noir::TreeSitter.each_named_child(node) do |child|
        content = Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "string_content"
      end
      content
    end

    private def build_function_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      index = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name_node = Noir::TreeSitter.field(node, "name")
        body_node = Noir::TreeSitter.field(node, "body")
        next unless name_node && body_node
        name = Noir::TreeSitter.node_text(name_node, source)
        # First occurrence wins. axum handlers are rarely overloaded
        # in the same file and the legacy analyzer behaved the same
        # way (first `fn name` match in the line scan).
        index[name] = body_node unless index.has_key?(name)
      end
      index
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
