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
      # Path-based test filtering now lives in
      # `RustEngine#parallel_file_scan` (see #1569 history). The
      # remaining `analyze_file` work is the cfg(test) region pass —
      # axum's source files mix production routes with
      # `#[cfg(test)] mod tests { ... }` blocks, which a path filter
      # alone can't tell apart.
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # `#[cfg(test)] mod tests { ... let app = Router::new().route(...); }`
      # is the canonical place doctests-as-unit-tests register routes in
      # Rust source — axum-extra exercises this heavily. The shared
      # `RustEngine.collect_cfg_test_regions` walks the cfg(test)-gated
      # blocks once per file; we filter route calls whose start byte
      # falls inside.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = include_callee ? build_function_index(root, source) : Hash(String, LibTreeSitter::TSNode).new

        walk_router_builders(root, source, "", test_regions) do |node, prefix|
          route = extract_route(node, source)
          next unless route

          path_str, methods, handler_name = route
          path_str = join_paths(prefix, path_str) unless prefix.empty?
          methods.each do |verb|
            details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
            endpoint = Endpoint.new(path_str, verb, details)

            if include_callee && handler_name && (body_node = function_index[handler_name]?)
              entries = Noir::RustCalleeExtractorTS.callees_in_body(body_node, source, path)
              attach_rust_callees(endpoint, entries)
            end

            endpoints << endpoint
          end
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

    # Walks Axum router builder chains with an active path prefix.
    # This keeps ordinary chained `.route(...)` behaviour while also
    # applying `.nest("/api", Router::new().route(...))` prefixes to
    # inline nested routers instead of emitting those inner routes at
    # the root.
    private def walk_router_builders(node : LibTreeSitter::TSNode,
                                     source : String,
                                     prefix : String,
                                     test_regions : Array(Tuple(Int32, Int32)),
                                     &block : LibTreeSitter::TSNode, String ->)
      if Noir::TreeSitter.node_type(node) == "call_expression"
        return if RustEngine.inside_test_region?(node, test_regions)

        if route_call?(node, source)
          block.call(node, prefix)
          walk_receiver_chain(node, source, prefix, test_regions, &block)
          return
        end

        if nest = extract_nest_call(node, source)
          nest_prefix, nested_router = nest
          walk_receiver_chain(node, source, prefix, test_regions, &block)
          walk_router_builders(nested_router, source, join_paths(prefix, nest_prefix), test_regions, &block)
          return
        end

        if merge_arg = extract_merge_call(node, source)
          walk_receiver_chain(node, source, prefix, test_regions, &block)
          walk_router_builders(merge_arg, source, prefix, test_regions, &block)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_router_builders(child, source, prefix, test_regions, &block)
      end
    end

    private def walk_receiver_chain(call : LibTreeSitter::TSNode,
                                    source : String,
                                    prefix : String,
                                    test_regions : Array(Tuple(Int32, Int32)),
                                    &block : LibTreeSitter::TSNode, String ->)
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      receiver = Noir::TreeSitter.field(function, "value")
      return unless receiver
      walk_router_builders(receiver, source, prefix, test_regions, &block)
    end

    private def extract_nest_call(call : LibTreeSitter::TSNode,
                                  source : String) : Tuple(String, LibTreeSitter::TSNode)?
      return unless field_call_name(call, source) == "nest"
      args = named_arguments(call)
      return unless args.size >= 2
      prefix = string_literal_text(args[0], source)
      return unless prefix
      {prefix, args[1]}
    end

    private def extract_merge_call(call : LibTreeSitter::TSNode,
                                   source : String) : LibTreeSitter::TSNode?
      return unless field_call_name(call, source) == "merge"
      args = named_arguments(call)
      args.first?
    end

    private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      field ? Noir::TreeSitter.node_text(field, source) : nil
    end

    # Returns `{path, http_method, handler_name?}` for a valid
    # `.route(path, verb(handler))` call, or `nil` when the shape
    # doesn't match. Returns a list of methods because Axum allows
    # chaining (`get(handler).post(handler)`); each verb in the
    # chain emits a separate endpoint.
    private def extract_route(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String), String?)?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      named = named_children(args)
      return if named.size < 2

      path = string_literal_text(named[0], source)
      return unless path

      methods, handler = decode_handler(named[1], source)
      {path, methods, handler}
    end

    # `get(handler)` → `{["GET"], "handler"}`.
    # `get(handler).post(other)` → `{["GET", "POST"], "handler"}`.
    # The chain is left-folded by tree-sitter, so we walk back from
    # the outermost call to the innermost `get(...)` collecting verbs
    # in declaration order. The handler captured is the FIRST
    # handler in the chain — every verb routes to *its own* handler
    # in real Axum code, but the legacy regex analyzer only tracked
    # one and we keep that behaviour for callee attribution. Falls
    # back to a single GET endpoint when the shape doesn't match.
    private def decode_handler(node : LibTreeSitter::TSNode, source : String) : Tuple(Array(String), String?)
      methods = [] of String
      handler : String? = nil

      cursor = node
      while Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn_node = Noir::TreeSitter.field(cursor, "function")
        break unless fn_node
        case Noir::TreeSitter.node_type(fn_node)
        when "identifier"
          # Innermost: `get(handler)`.
          verb = Noir::TreeSitter.node_text(fn_node, source).downcase
          if HTTP_VERBS.includes?(verb)
            methods.unshift(verb.upcase)
          end
          handler ||= first_identifier_argument(cursor, source)
          break
        when "field_expression"
          # Chained: `<inner>.post(...)`. Field is the verb.
          field = Noir::TreeSitter.field(fn_node, "field")
          if field
            verb = Noir::TreeSitter.node_text(field, source).downcase
            methods.unshift(verb.upcase) if HTTP_VERBS.includes?(verb)
          end
          inner = Noir::TreeSitter.field(fn_node, "value")
          break unless inner
          cursor = inner
        else
          break
        end
      end

      methods << "GET" if methods.empty?
      {methods, handler}
    end

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
      end
      nil
    end

    private def named_arguments(call : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      args = Noir::TreeSitter.field(call, "arguments")
      return [] of LibTreeSitter::TSNode unless args
      named_children(args)
    end

    private def named_children(node : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named
    end

    private def join_paths(prefix : String, path : String) : String
      "#{prefix.rstrip('/')}/#{path.lstrip('/')}"
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
