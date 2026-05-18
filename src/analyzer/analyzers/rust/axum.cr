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
      # Rust's `tests/` directory at the crate root holds integration
      # tests that never ship as production endpoints; `*_test.rs` /
      # `*_tests.rs` follow the same convention for unit-test files.
      # Skip them up-front so axum's own `axum-macros/tests/...` (full
      # `fn main()` files exercising the macros) and similarly-named
      # files in user projects don't pollute the endpoint set.
      return endpoints if test_only_path?(path)
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # `#[cfg(test)] mod tests { ... let app = Router::new().route(...); }`
      # is the canonical place doctests-as-unit-tests register routes in
      # Rust source — axum-extra exercises this heavily. Find each
      # cfg(test)-gated block's byte range up-front; routes whose call
      # node starts inside one are unit-test fixtures, not endpoints.
      test_regions = collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = include_callee ? build_function_index(root, source) : Hash(String, LibTreeSitter::TSNode).new

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          next unless route_call?(node, source)
          next if inside_test_region?(node, test_regions)

          route = extract_route(node, source)
          next unless route

          path_str, methods, handler_name = route
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

    # Cargo convention: every `.rs` immediately under a crate's `tests/`
    # directory is an integration test binary, never a production
    # endpoint. We accept the slightly broader `**/tests/**/*.rs` match
    # because real Rust apps almost never park production code in a
    # directory named `tests`; the rare false negative is preferable to
    # leaking framework internals like axum-extra's mod-test fixtures.
    private def test_only_path?(path : String) : Bool
      return true if path.includes?("/tests/")
      base = File.basename(path)
      base.ends_with?("_test.rs") || base.ends_with?("_tests.rs")
    end

    # Scan the source for `#[cfg(test)]` annotations, then capture the
    # byte range of the following `mod`/`fn`/`impl` block via simple
    # brace counting. String/char literals are skipped so a `{` inside
    # `"foo {"` doesn't shift the depth. The annotated item is always
    # one of these — axum's pattern never gates a `const`/`static` —
    # so we don't try to handle non-block items.
    private def collect_cfg_test_regions(source : String) : Array(Tuple(Int32, Int32))
      regions = [] of Tuple(Int32, Int32)
      bytes = source.to_slice
      pattern = /\#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]/
      source.scan(pattern) do |match|
        attr_start = match.begin || next
        brace_idx = find_block_open_brace(bytes, attr_start + 1)
        next unless brace_idx
        close_idx = find_matching_close_brace(bytes, brace_idx)
        next unless close_idx
        regions << {attr_start, close_idx + 1}
      end
      regions
    end

    private def find_block_open_brace(bytes : Slice(UInt8), from : Int32) : Int32?
      i = from
      while i < bytes.size
        c = bytes[i]
        case c
        when '"'.ord then i = skip_string_literal(bytes, i)
        when '\''.ord then i = skip_char_or_lifetime(bytes, i)
        when '/'.ord
          if i + 1 < bytes.size && bytes[i + 1] == '/'.ord
            i = skip_line_comment(bytes, i)
          elsif i + 1 < bytes.size && bytes[i + 1] == '*'.ord
            i = skip_block_comment(bytes, i)
          else
            i += 1
          end
        when '{'.ord then return i
        else i += 1
        end
      end
      nil
    end

    private def find_matching_close_brace(bytes : Slice(UInt8), open_idx : Int32) : Int32?
      depth = 1
      i = open_idx + 1
      while i < bytes.size && depth > 0
        c = bytes[i]
        case c
        when '"'.ord then i = skip_string_literal(bytes, i); next
        when '\''.ord then i = skip_char_or_lifetime(bytes, i); next
        when '/'.ord
          if i + 1 < bytes.size && bytes[i + 1] == '/'.ord
            i = skip_line_comment(bytes, i); next
          elsif i + 1 < bytes.size && bytes[i + 1] == '*'.ord
            i = skip_block_comment(bytes, i); next
          end
        when '{'.ord then depth += 1
        when '}'.ord then depth -= 1
        end
        i += 1
      end
      depth == 0 ? i - 1 : nil
    end

    private def skip_string_literal(bytes : Slice(UInt8), from : Int32) : Int32
      i = from + 1
      while i < bytes.size
        c = bytes[i]
        if c == '\\'.ord
          i += 2
          next
        end
        if c == '"'.ord
          return i + 1
        end
        i += 1
      end
      i
    end

    # Distinguish Rust char literals (`'x'`, `'\n'`, `'\u{...}'`) from
    # lifetime annotations (`'a`, `'static`). A lifetime starts with
    # `'` followed by an identifier-start char and is NOT immediately
    # closed by another quote — most importantly, it never contains
    # `{`/`}` so we can just step past the leading quote and keep
    # scanning. A char literal does contain interior bytes we want to
    # skip so a `'{'` doesn't perturb brace depth.
    private def skip_char_or_lifetime(bytes : Slice(UInt8), from : Int32) : Int32
      # `'x'` (3 bytes): bytes[from+2] is `'`.
      if from + 2 < bytes.size && bytes[from + 2] == '\''.ord
        return from + 3
      end
      # `'\<esc>'`: bytes[from+1] is `\`, scan for matching `'`.
      if from + 1 < bytes.size && bytes[from + 1] == '\\'.ord
        i = from + 2
        while i < bytes.size
          c = bytes[i]
          if c == '\\'.ord
            i += 2
            next
          end
          return i + 1 if c == '\''.ord
          i += 1
        end
        return i
      end
      # Otherwise treat as lifetime: only consume the apostrophe.
      from + 1
    end

    private def skip_line_comment(bytes : Slice(UInt8), from : Int32) : Int32
      i = from
      while i < bytes.size && bytes[i] != '\n'.ord
        i += 1
      end
      i
    end

    private def skip_block_comment(bytes : Slice(UInt8), from : Int32) : Int32
      i = from + 2
      while i + 1 < bytes.size
        if bytes[i] == '*'.ord && bytes[i + 1] == '/'.ord
          return i + 2
        end
        i += 1
      end
      bytes.size
    end

    private def inside_test_region?(node : LibTreeSitter::TSNode, regions : Array(Tuple(Int32, Int32))) : Bool
      return false if regions.empty?
      start_byte = LibTreeSitter.ts_node_start_byte(node).to_i
      regions.any? { |s, e| start_byte >= s && start_byte < e }
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
    # doesn't match. Returns a list of methods because Axum allows
    # chaining (`get(handler).post(handler)`); each verb in the
    # chain emits a separate endpoint.
    private def extract_route(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String), String?)?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |c| named << c }
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
