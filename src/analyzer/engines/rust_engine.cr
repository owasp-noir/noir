require "../../models/analyzer"
require "./file_scan_engine"
require "../../miniparsers/rust_callee_extractor"
require "../../miniparsers/rust_callee_extractor_ts"
require "../../miniparsers/rust_struct_fields"
require "../../miniparsers/rust_use_imports"
require "../../ext/tree_sitter/tree_sitter"

module Analyzer::Rust
  abstract class RustEngine < FileScanEngine
    # Lower-case verb names the route macros and builders are spelled with.
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    # Expand `any` / `all` (case-insensitive) into the seven
    # canonical HTTP methods. Anything else passes through as a
    # single-element list.
    def self.fan_out_verbs(verb : String) : Array(String)
      case verb.upcase
      when "ANY", "ALL"
        ANY_ROUTE_HTTP_METHODS
      else
        [verb]
      end
    end

    # `.rs` sources from the extension index; test-path and crate-root
    # gating lives in `scan_accepts?`.
    protected def scan_target_files : Array(String)
      get_files_by_extension(".rs")
    end

    protected def scan_accepts?(path : String) : Bool
      return false if RustEngine.test_path?(base_relative_path(path))
      path_under_crate_roots?(path, crate_roots)
    end

    # The Cargo dependencies that identify this analyzer's framework. An
    # analyzer that declares them is only shown files inside a crate that
    # actually depends on one — without that, every Rust analyzer sees every
    # `.rs` file in the scan and the route DSLs are close enough to collide.
    # axum's `.route("/foo", get(handler))` and actix's glob-imported
    # `.route("/foo", get().to(handler))` are the same tree, so actix read
    # axum's whole router as its own. Default is empty, meaning no gate.
    protected def crate_dependencies : Array(String)
      [] of String
    end

    # Directories holding a `Cargo.toml` that depends on one of
    # `crate_dependencies`. Empty when the analyzer declares no dependencies,
    # and also empty when the scan has no matching manifest at all — in which
    # case `path_under_crate_roots?` waves everything through, so a source
    # tree checked out without its manifest keeps working exactly as before.
    private def crate_roots : Array(String)
      @crate_roots ||= compute_crate_roots
    end

    @crate_roots : Array(String)?

    private def compute_crate_roots : Array(String)
      dependencies = crate_dependencies
      return [] of String if dependencies.empty?

      patterns = dependencies.map { |name| cargo_dependency_re(name) }
      roots = [] of String
      all_files.each do |file|
        next unless File.basename(file) == "Cargo.toml"
        begin
          content = read_file_content(file)
        rescue
          next
        end
        next unless patterns.any? { |pattern| content.matches?(pattern) }
        root = Noir::PathScope.normalize_root(File.dirname(file))
        roots << root unless roots.includes?(root)
      end
      roots
    end

    # `axum = "0.7"`, `axum = { path = "…" }`, `axum.workspace = true` and
    # `[dependencies.axum]` all declare the dependency. Anchored on the key so
    # `actix-web` does not match the `actix-web-lab` line above it.
    private def cargo_dependency_re(name : String) : Regex
      escaped = Regex.escape(name)
      Regex.new("^\\s*(?:#{escaped}\\s*[=.]|\\[(?:[\\w.-]+\\.)?dependencies\\.#{escaped}\\])", Regex::Options::MULTILINE)
    end

    # The key that scopes a project-wide mount / prefix index for `path`: its
    # Cargo workspace root, else its nearest crate root, else the scan base.
    # Keying by scan base alone let two unrelated crates scanned as one `-b`
    # share an index, so one crate's `scope("/a")` prefixed the other's
    # same-named handlers. A workspace stays one scope because its member
    # crates mount each other's routers.
    protected def crate_scope_for(path : String) : String
      manifests = cargo_manifest_dirs
      return configured_base_for(path) if manifests.empty?

      dir = File.dirname(Noir::PathScope.expand(path))
      nearest = nil
      workspace = nil
      loop do
        unless (is_workspace = manifests[dir]?).nil?
          nearest ||= dir
          workspace = dir if is_workspace
        end
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      workspace || nearest || configured_base_for(path)
    end

    # Normalized directory of every scanned `Cargo.toml` => whether it
    # declares a `[workspace]`.
    private def cargo_manifest_dirs : Hash(String, Bool)
      @cargo_manifest_dirs ||= begin
        dirs = {} of String => Bool
        all_files.each do |file|
          next unless File.basename(file) == "Cargo.toml"
          content = read_file_content(file) rescue ""
          dirs[Noir::PathScope.normalize_root(File.dirname(file))] = content.matches?(CARGO_WORKSPACE_RE)
        end
        dirs
      end
    end

    @cargo_manifest_dirs : Hash(String, Bool)?

    CARGO_WORKSPACE_RE = /(?m)^\s*\[workspace\]/

    private def path_under_crate_roots?(path : String, roots : Array(String)) : Bool
      return true if roots.empty?

      expanded = Noir::PathScope.expand(path)
      roots.any? { |root| Noir::PathScope.under_normalized_root?(expanded, root) }
    end

    # Workspace test crates are named after the convention without being
    # the literal `tests/` segment: `rwf-tests`, `tests-fuzz`,
    # `playwright-tests`, `suspense_tests`. Plural `tests` needs a `-`/`_`
    # delimiter so `contests/` and `latest/` stay out; singular `test-app`
    # / `test_only` are deliberately not matched. `e2e` / `playwright` count
    # only as the whole segment, optionally with a `-test(s)` / `_test(s)`
    # suffix: `e2e-encryption/` and `api/e2e_keys/` are Matrix-style
    # end-to-end *encryption* code and serve real routes. Applied to the
    # rooted scan-base-relative path, like the `/tests/` check.
    TEST_CRATE_DIR_RE = %r{/(?:[\w.-]+[-_])?tests(?:[-_][\w.-]+)?/|/(?:e2e|playwright)(?:[-_]tests?)?/}

    # Cargo convention: every `.rs` immediately under a crate's
    # `tests/` directory is an integration-test binary, never a
    # production endpoint. The `_test.rs` / `_tests.rs` suffix is
    # equally rigid for unit tests in sibling files. Framework
    # repos (rocket/Rocket's `core/codegen/tests/`, actix-web's
    # `actix-web-codegen/tests/`, poem's `poem-openapi/tests/`)
    # all park hundreds of route registrations under one of these
    # patterns. Promoted from `axum.cr#test_only_path?` (#1569) to
    # the shared engine so the rest of the Rust family benefits.
    #
    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. Cargo's conventions are relative to the
    # crate, so matching the absolute path let a directory *above* the
    # scan base decide the answer: the same tree cloned into
    # `~/work/tests/myapp` reported 0 endpoints instead of 220.
    def self.test_path?(relative_path : String) : Bool
      return true if relative_path.includes?("/tests/")
      return true if relative_path.matches?(TEST_CRATE_DIR_RE)
      # Cargo's `benches/` directory holds `cargo bench` harnesses
      # (`Router::new().route(...)` scaffolding for throughput tests),
      # never production endpoints — axum/tide park route-building
      # benchmarks here. Exclude it like `tests/`.
      return true if relative_path.includes?("/benches/")
      base = File.basename(relative_path)
      base == "tests.rs" || base.ends_with?("_test.rs") || base.ends_with?("_tests.rs")
    end

    # Scan the source for `#[cfg(test)]` annotations, then capture
    # the byte range of the following `mod`/`fn`/`impl` block via
    # simple brace counting. String/char literals are skipped so a
    # `{` inside `"foo {"` doesn't shift the depth. Rust lifetimes
    # like `'a` look like char literals to a naive quote scanner
    # and would otherwise drop the close-brace search into oblivion
    # — see `skip_char_or_lifetime`.
    #
    # Shared with all Rust analyzers: axum's `extract/path/mod.rs`,
    # salvo's `crates/core/src/routing.rs`, and similar framework
    # source files mix production routes with `#[cfg(test)] mod
    # tests { ... }` blocks. Each analyzer that uses tree-sitter
    # can call this once per file, then drop any route call whose
    # `ts_node_start_byte` falls in one of the returned ranges.
    def self.collect_cfg_test_regions(source : String) : Array(Tuple(Int32, Int32))
      regions = [] of Tuple(Int32, Int32)
      bytes = source.to_slice
      pattern = /\#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]/
      source.scan(pattern) do |match|
        # Byte offset: the scan below and tree-sitter's ranges are both in
        # bytes, and `begin` counts chars, so non-ASCII text above the
        # attribute shifted the region back over production code.
        attr_start = match.byte_begin
        brace_idx = find_block_open_brace(bytes, attr_start + 1)
        next unless brace_idx
        close_idx = find_matching_close_brace(bytes, brace_idx)
        next unless close_idx
        regions << {attr_start, close_idx + 1}
      end
      regions
    end

    def self.inside_test_region?(node : LibTreeSitter::TSNode, regions : Array(Tuple(Int32, Int32))) : Bool
      return false if regions.empty?
      start_byte = LibTreeSitter.ts_node_start_byte(node).to_i
      regions.any? { |s, e| start_byte >= s && start_byte < e }
    end

    # Returns nil when the item ends at a top-level `;` before any `{`
    # (`mod tests;`, `use …;`, `const X: [u8; 4] = …;`): that item has
    # no block, and the next `{` belongs to the following production item.
    # Likewise at a `}` before any `{`: the attribute was on a struct field
    # or enum variant and the enclosing block just closed.
    private def self.find_block_open_brace(bytes : Slice(UInt8), from : Int32) : Int32?
      i = from
      nesting = 0
      while i < bytes.size
        c = bytes[i]
        case c
        when '"'.ord  then i = skip_string_literal(bytes, i)
        when '\''.ord then i = skip_char_or_lifetime(bytes, i)
        when 'r'.ord, 'b'.ord
          # Raw strings (`r"…"`, `r#"…"#`, `br#"…"#`) routinely embed `{`
          # / `}` — e.g. a JSON body in a `#[cfg(test)]` test — and must
          # be skipped whole or the brace matcher mis-counts depth.
          i = try_skip_raw_string(bytes, i) || i + 1
        when '/'.ord
          if i + 1 < bytes.size && bytes[i + 1] == '/'.ord
            i = skip_line_comment(bytes, i)
          elsif i + 1 < bytes.size && bytes[i + 1] == '*'.ord
            i = skip_block_comment(bytes, i)
          else
            i += 1
          end
        when '{'.ord then return i
        when '}'.ord then return # left the enclosing block: a field or variant
        when '('.ord, '['.ord
          nesting += 1
          i += 1
        when ')'.ord, ']'.ord
          nesting -= 1 if nesting > 0
          i += 1
        when ';'.ord
          return if nesting == 0
          i += 1
        else i += 1
        end
      end
      nil
    end

    private def self.find_matching_close_brace(bytes : Slice(UInt8), open_idx : Int32) : Int32?
      depth = 1
      i = open_idx + 1
      while i < bytes.size && depth > 0
        c = bytes[i]
        case c
        when '"'.ord  then i = skip_string_literal(bytes, i); next
        when '\''.ord then i = skip_char_or_lifetime(bytes, i); next
        when 'r'.ord, 'b'.ord
          if nb = try_skip_raw_string(bytes, i)
            i = nb
            next
          end
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

    # If `from` begins a Rust raw string literal — `r"…"`, `r#"…"#`,
    # `r##"…"##`, or the byte-string `br"…"` / `br#"…"#` forms — return
    # the index just past its terminator; otherwise `nil`. The closer is
    # a `"` followed by exactly the same number of `#` as the opener, so
    # interior quotes and braces are consumed verbatim. In valid Rust an
    # `r` / `br` immediately followed by `#`* `"` is unambiguously a raw
    # string (a bare `r#ident` raw identifier has no quote), so ordinary
    # identifiers and byte/binary literals (`b'x'`, `b"x"`, `0b10`) fall
    # through to `nil`.
    private def self.try_skip_raw_string(bytes : Slice(UInt8), from : Int32) : Int32?
      i = from
      if bytes[i] == 'b'.ord
        i += 1
        return unless i < bytes.size && bytes[i] == 'r'.ord
      end
      return unless i < bytes.size && bytes[i] == 'r'.ord
      i += 1
      hashes = 0
      while i < bytes.size && bytes[i] == '#'.ord
        hashes += 1
        i += 1
      end
      return unless i < bytes.size && bytes[i] == '"'.ord
      i += 1
      while i < bytes.size
        if bytes[i] == '"'.ord
          j = i + 1
          k = 0
          while k < hashes && j < bytes.size && bytes[j] == '#'.ord
            k += 1
            j += 1
          end
          return j if k == hashes
        end
        i += 1
      end
      bytes.size
    end

    private def self.skip_string_literal(bytes : Slice(UInt8), from : Int32) : Int32
      i = from + 1
      while i < bytes.size
        c = bytes[i]
        if c == '\\'.ord
          i += 2
          next
        end
        return i + 1 if c == '"'.ord
        i += 1
      end
      i
    end

    private def self.skip_char_or_lifetime(bytes : Slice(UInt8), from : Int32) : Int32
      if from + 2 < bytes.size && bytes[from + 2] == '\''.ord
        return from + 3
      end
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
      from + 1
    end

    private def self.skip_line_comment(bytes : Slice(UInt8), from : Int32) : Int32
      i = from
      while i < bytes.size && bytes[i] != '\n'.ord
        i += 1
      end
      i
    end

    private def self.skip_block_comment(bytes : Slice(UInt8), from : Int32) : Int32
      i = from + 2
      while i + 1 < bytes.size
        return i + 2 if bytes[i] == '*'.ord && bytes[i + 1] == '/'.ord
        i += 1
      end
      bytes.size
    end

    protected def attach_rust_callees(endpoint : Endpoint, callees : Array(Noir::RustCalleeExtractor::Entry))
      Noir::RustCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_rust_function_body_with_end(lines : Array(String), start_index : Int32) : Tuple(String, Int32, Int32)?
      return if start_index >= lines.size
      return if Noir::RustCalleeExtractor.strip_comment(lines[start_index]).includes?(";")

      body_lines = [] of String
      body_start_line = start_index + 2
      found_opening_brace = false
      depth = 0
      in_block_comment = false

      (start_index...lines.size).each do |index|
        raw_line = lines[index]
        line, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(raw_line, in_block_comment)

        unless found_opening_brace
          return if index > start_index && line.strip.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+[A-Za-z_]\w*\b/)

          brace_index = line.index('{')
          next unless brace_index

          found_opening_brace = true
          depth = 1
          tail = line[(brace_index + 1)..].strip
          body_start_line = index + 1

          if close_index = tail.index('}')
            open_count = tail.count('{')
            close_count = tail.count('}')
            if depth + open_count - close_count <= 0
              close_index = tail.rindex('}') || close_index
              return {tail[0, close_index].strip, body_start_line, index}
            end
          end

          if tail.empty?
            body_start_line = index + 2
          else
            body_lines << tail
            depth += tail.count('{') - tail.count('}')
          end
          next
        end

        stripped = line.strip
        open_count = stripped.count('{')
        close_count = stripped.count('}')

        if close_count > 0 && depth + open_count - close_count <= 0
          if close_index = line.index('}')
            close_index = line.rindex('}') || close_index
            before_close = line[0, close_index].strip
            body_lines << before_close unless before_close.empty?
          end
          return {body_lines.join("\n"), body_start_line, index}
        end

        body_lines << raw_line
        depth += open_count - close_count
      end

      return unless found_opening_brace

      {body_lines.join("\n"), body_start_line, lines.size - 1}
    end

    # ---- Shared tree-sitter walking helpers -----------------------------
    #
    # These were 47 byte-identical private copies across the ten Rust
    # framework adapters. They are `protected`, so an adapter that needs
    # different behaviour still overrides — and three do, deliberately:
    #
    #   * `warp#call_function_text` returns text only for a
    #     `scoped_identifier`, nil otherwise.
    #   * `axum#build_function_index` is an overload pair that tracks
    #     module scope while descending.
    #   * `actix_web#find_paired_function` differs from the shape below.
    #
    # Those three keep their own versions; Crystal dispatches to the
    # subclass, so the helpers here that call them (`each_routing_pair` →
    # `find_paired_function`, `build_function_index` → `walk`) still get
    # the adapter's behaviour.

    # Yield `node` and every named descendant, depth-first.
    protected def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end

    # The first named child of `node` whose type is `type`.
    protected def find_named_child(node : LibTreeSitter::TSNode, type : String) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(node) do |child|
        return child if Noir::TreeSitter.node_type(child) == type
      end
      nil
    end

    # `function_name => function_item` over the whole tree, first
    # definition winning.
    protected def build_function_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
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

    # 1-based line of a method call's name. A chained call node starts at
    # the chain's first token, so `Router::new()\n.route("/a", …)\n.route("/b", …)`
    # would put every route on the `Router::new()` line.
    protected def call_line(call : LibTreeSitter::TSNode) : Int32
      fn_node = Noir::TreeSitter.field(call, "function")
      if fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression" && (field = Noir::TreeSitter.field(fn_node, "field"))
        return Noir::TreeSitter.node_start_row(field) + 1
      end
      Noir::TreeSitter.node_start_row(call) + 1
    end

    # The callee text of a `call_expression` (`foo`, `Bar::baz`, …).
    protected def call_function_text(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node
      Noir::TreeSitter.node_text(fn_node, source)
    end

    # Walk `node`'s children at every depth and yield `(attribute_item,
    # function_item)` pairs where the attribute immediately precedes
    # the function (skipping intermediate attribute_items and doc
    # comments). This matches how `#[get(...)] async fn handler` is
    # laid out in the AST — both are top-level siblings, not parent /
    # child.
    # `depth` bounds the descent. The recursive call sits *outside* the
    # `each_named_child` block (children are materialised first so
    # `find_paired_function` can look ahead), so the depth guard inside
    # `each_named_child` has already unwound by the time we recurse and
    # cannot see this walk. A `.rs` file nesting thousands of blocks deep
    # — generated code, or a hand-built stress case — would otherwise run
    # the fiber stack out, and a stack overflow aborts the process rather
    # than failing the one file.
    protected def each_routing_pair(node : LibTreeSitter::TSNode, depth : Int32 = 0, &block : LibTreeSitter::TSNode, LibTreeSitter::TSNode ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named.each_with_index do |child, idx|
        if Noir::TreeSitter.node_type(child) == "attribute_item"
          pair_function = find_paired_function(named, idx + 1)
          block.call(child, pair_function) if pair_function
        end
        each_routing_pair(child, depth + 1, &block)
      end
    end

    # The `function_item` that `named[start...]` leads to, skipping further
    # attributes and comments. Anything else means the attribute does not
    # decorate a function, so there is no pair.
    protected def find_paired_function(named : Array(LibTreeSitter::TSNode), start : Int32) : LibTreeSitter::TSNode?
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

    # The full text of a `string_literal`, concatenating every
    # `string_content` and `escape_sequence` child.
    #
    # tree-sitter-rust splits a literal at each escape — `"/page-{id:\d+}"`
    # parses as string_content `/page-{id:`, escape_sequence `\d`,
    # string_content `+}` — so reading only the first `string_content`
    # truncates any path carrying one. That is what this method used to do,
    # and it is why a route registered as `.at("/page-{id:\d+}")` was
    # reported as `/page-{id:`.
    #
    # Returns nil for a literal with no content children (a genuinely empty
    # `""`), which is what every caller's `|| ""` fallback expects.
    protected def string_content(string_literal : LibTreeSitter::TSNode, source : String) : String?
      parts = [] of String
      Noir::TreeSitter.each_named_child(string_literal) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_content", "escape_sequence"
          parts << Noir::TreeSitter.node_text(child, source)
        end
      end
      parts.empty? ? nil : parts.join
    end

    # `string_content` with a type guard, for callers that hand over an
    # arbitrary argument node and want nil when it is not a literal (an
    # identifier, a macro call, a method chain). Keeping this separate
    # preserves the guard that `axum#string_literal_text` carried — its
    # callers pass `args[0]` / `named[0]` straight from a call expression.
    protected def string_literal_content(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "string_literal"
      string_content(node, source)
    end

    # The first string literal anywhere under `node`, depth-first.
    #
    # Ten adapters carried their own copy of this walk. Eight read only the
    # first `string_content` child and truncated at escapes; actix_web and
    # axum had each independently found that bug and written their own
    # escape-aware reader, complete with a comment explaining it — the
    # knowledge existed twice in the tree and never reached the other eight.
    protected def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        next unless Noir::TreeSitter.node_type(child) == "string_literal"
        result = string_content(child, source)
      end
      result
    end

    # The `Handler` for a resolved `function_item`: its name and the line of
    # that name (the `fn` line, past any attributes or doc comments stacked
    # above it). `Endpoint` is a struct, so callers assign the result.
    protected def rust_handler(function : LibTreeSitter::TSNode, source : String, path : String) : Handler?
      name = Noir::TreeSitter.field(function, "name") || return
      Handler.new(Noir::TreeSitter.node_text(name, source), path, Noir::TreeSitter.node_start_row(name) + 1)
    end

    # The top-level `function_item` whose name sits on `line` (1-based), the
    # definition `resolve_rust_fn` reports. Picking by line, not by name,
    # keeps a same-named impl method or cfg twin from standing in for it.
    protected def top_level_fn_at(root : LibTreeSitter::TSNode, line : Int32) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(root) do |item|
        next unless Noir::TreeSitter.node_type(item) == "function_item"
        name_node = Noir::TreeSitter.field(item, "name") || next
        return item if Noir::TreeSitter.node_start_row(name_node) + 1 == line
      end
      nil
    end

    # `rust_handler` for a builder-registered handler name looked up in the
    # same file's `build_function_index`. Only an unqualified name is exact:
    # `get(index)` can only mean a fn in scope, and a local fn of that name
    # cannot coexist with an imported one, whereas `get(other::index)` names
    # a different module's fn that merely shares the leaf.
    protected def local_handler(name : String, function_index : Hash(String, LibTreeSitter::TSNode),
                                source : String, path : String) : Handler?
      return if name.includes?("::")
      function = function_index[name]? || return
      rust_handler(function, source, path)
    end

    STRUCT_DECL_RE = /\bstruct\s+([A-Za-z_]\w*)/

    @struct_decl_files : Hash(String, Array(String))?
    @struct_fields_by_file = {} of String => Hash(String, Noir::RustStructFields::Shape)
    @struct_index_mutex = Mutex.new

    # A struct's wire field names. `complete` is false when a
    # `#[serde(flatten)]` field's type could not be read (an enum, a map
    # catch-all, an external type): the body carries more than `names`.
    record WireFields, names : Array(String), complete : Bool

    # Wire fields of the named-field struct `name` (see
    # `Noir::RustStructFields`), as seen from `from_path`. The definition in
    # `from_path` wins; otherwise every same-crate definition must agree, so
    # two unrelated `struct Data`s in one crate resolve to nothing rather
    # than to the wrong one.
    protected def rust_struct_fields(name : String, from_path : String) : WireFields?
      struct_fields_named(name, from_path, 0)
    end

    private def struct_fields_named(name : String, from_path : String, depth : Int32) : WireFields?
      files = @struct_index_mutex.synchronize { struct_decl_files[name]?.try(&.dup) } || return
      return expanded_struct_fields(from_path, name, depth) if files.includes?(from_path)
      scope = crate_scope_for(from_path)
      found = files.select { |f| crate_scope_for(f) == scope && struct_fields_of_file(f).has_key?(name) }
        .map { |f| expanded_struct_fields(f, name, depth) }.uniq!
      found.size == 1 ? found.first : nil
    end

    # Fields of the struct `ref` names from `from_path`: through the file's
    # imports, else (a bare name nothing imports, e.g. via a glob) a
    # same-crate name with one definition. A type imported from outside the
    # scan is unknown.
    private def struct_ref_fields(ref : String, from_path : String, depth : Int32) : WireFields?
      if found = resolve_rust_item(ref, from_path, RustItemKind::Struct)
        return expanded_struct_fields(found[0], found[1], depth)
      end
      return if ref.includes?("::") || rust_imported?(ref, from_path)
      struct_fields_named(ref, from_path, depth)
    end

    MAX_FLATTEN_DEPTH = 4
    FLATTEN_TYPE_RE   = /\A(?:Option\s*<\s*)?((?:[A-Za-z_]\w*::)*[A-Za-z_]\w*)\s*(?:[<>]|\z)/

    # `leaf`'s fields in `file`, each `#[serde(flatten)]` field replaced by
    # its type's fields (the type resolved from `file`). A flattened type
    # that is not a readable struct leaves the result incomplete, so the
    # caller adds its placeholder instead of claiming the list is whole.
    private def expanded_struct_fields(file : String, leaf : String, depth : Int32) : WireFields?
      shape = struct_fields_of_file(file)[leaf]? || return
      return WireFields.new(shape.fields, true) if shape.flattened.empty?
      names = shape.fields.dup
      complete = true
      shape.flattened.each do |type|
        inner = depth < MAX_FLATTEN_DEPTH ? type.match(FLATTEN_TYPE_RE).try { |m| struct_ref_fields(m[1], file, depth + 1) } : nil
        complete = false unless inner && inner.complete
        inner.try &.names.each { |field| names << field unless names.includes?(field) }
      end
      WireFields.new(names, complete)
    end

    # Extractor => {param location, name used when its type's fields are unknown}.
    EXTRACTOR_KINDS = {"Query" => {"query", "query"}, "Json" => {"json", "body"}, "Form" => {"form", "form"}}

    # The type an extractor decodes into, when it is a plain (possibly
    # module-qualified, possibly generic) name: `Json<CreatePost>`,
    # `web::Query<api::Params>`, `Json<Record<Data>>`, deserr's
    # `AwebJson<T, E>` / `AwebQueryParameter<T, E>`. `Json<Vec<T>>` is a
    # JSON array of `T`, so its params are `T`'s fields.
    EXTRACTOR_TARGET_RES = EXTRACTOR_KINDS.keys.to_h do |kind|
      {kind, /(?<!\w)(?:Aweb)?#{kind}(?:Parameter)?\s*<\s*(?:(?:(?:std::)?vec::)?Vec\s*<\s*)?((?:[A-Za-z_]\w*::)*[A-Za-z_]\w*)\s*[<>,]/}
    end

    # Push the params a `kind` extractor parameter (its source `text`)
    # reads: the wire field names of the type it decodes into, resolved from
    # `path` (a field-less struct reads none), else the generic placeholder.
    # `generics` are the handler fn's own type parameters: `Json<T>` under
    # `fn h<T: DeserializeOwned>` names no struct.
    protected def push_extractor_params(text : String, kind : String, endpoint : Endpoint, path : String?,
                                        generics : Array(String) = [] of String)
      location, placeholder = EXTRACTOR_KINDS[kind]
      fields = path ? extractor_fields(text, kind, path, generics) : nil
      fields.try &.names.each { |name| endpoint.push_param(Param.new(name, "", location)) }
      endpoint.push_param(Param.new(placeholder, "", location)) unless fields && fields.complete
    end

    private def extractor_fields(text : String, kind : String, path : String, generics : Array(String)) : WireFields?
      type = text.match(EXTRACTOR_TARGET_RES[kind]).try(&.[1]) || return
      return if generics.includes?(type)
      struct_ref_fields(type, path, 0)
    end

    # Names of a fn item's type parameters (`fn h<T: X, U>` => T, U).
    protected def fn_type_param_names(function : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      params = Noir::TreeSitter.field(function, "type_parameters") || return names
      Noir::TreeSitter.each_named_child(params) do |param|
        node = Noir::TreeSitter.node_type(param) == "type_identifier" ? param : (Noir::TreeSitter.field(param, "left") || Noir::TreeSitter.field(param, "name"))
        names << Noir::TreeSitter.node_text(node, source) if node
      end
      names
    end

    private def struct_decl_files : Hash(String, Array(String))
      @struct_decl_files ||= begin
        index = {} of String => Array(String)
        get_files_by_extension(".rs").each do |file|
          next if RustEngine.test_path?(base_relative_path(file))
          read_file_content(file).scan(STRUCT_DECL_RE) do |m|
            list = (index[m[1]] ||= [] of String)
            list << file unless list.includes?(file)
          end
        end
        index
      end
    end

    # ---- Cross-file item resolution -------------------------------------
    #
    # A route names its handler the way the routing file sees it:
    # `.to(create_post)` after `use my_api::post::create::create_post;`,
    # `.to(handlers::get_post)`, `.to(crate::api::list)`. These resolve that
    # name through the file's `use` imports, `crate` / `self` / `super`,
    # child modules (`foo.rs` / `foo/mod.rs`) and the scan's workspace crates
    # (`[package]` / `[lib]` name in `Cargo.toml`) to the file that defines
    # it, following `pub use` re-exports. A name that does not resolve to a
    # definition in a scanned file resolves to nil, never to a guess.

    @rust_rs_files : Hash(String, String)?
    @rust_crate_roots : Tuple(Hash(String, String), Set(String))?
    @rust_imports_by_file = {} of String => Noir::RustUseImports::Imports
    @rust_resolve_mutex = Mutex.new
    @rust_resolve_memo = {} of String => Tuple(String, String)?

    enum RustItemKind
      Fn
      Struct
    end

    # `{file, fn name, line}` of the top-level fn `ref` names from `from_path`.
    protected def resolve_rust_fn(ref : String, from_path : String) : Tuple(String, String, Int32)?
      found = resolve_rust_item(ref, from_path, RustItemKind::Fn) || return
      file, leaf = found
      {file, leaf, rust_imports(file).fns[leaf]}
    end

    # Whether `from_path` brings `name` in with an explicit `use`. A type
    # imported that way and still unresolved comes from outside the scan,
    # so a same-named struct of the scan must not stand in for it.
    protected def rust_imported?(name : String, from_path : String) : Bool
      from = rust_rs_files[Noir::PathScope.expand(from_path)]? || return false
      imports = rust_imports(from)
      imports.names.has_key?(name) || imports.ambiguous.includes?(name)
    end

    private def struct_fields_of_file(file : String) : Hash(String, Noir::RustStructFields::Shape)
      cached = @struct_index_mutex.synchronize { @struct_fields_by_file[file]? }
      return cached if cached
      fields = Noir::RustStructFields.parse(read_file_content(file))
      @struct_index_mutex.synchronize { @struct_fields_by_file[file] ||= fields }
    end

    private def rust_defines?(kind : RustItemKind, file : String, leaf : String) : Bool
      kind.fn? ? rust_imports(file).fns.has_key?(leaf) : struct_fields_of_file(file).has_key?(leaf)
    end

    # `{file, leaf}` of the item `ref` names from `from_path`, memoised per
    # `(kind, file, ref)`.
    private def resolve_rust_item(ref : String, from_path : String, kind : RustItemKind) : Tuple(String, String)?
      from = rust_rs_files[Noir::PathScope.expand(from_path)]? || return
      key = "#{kind}\0#{from}\0#{ref}"
      memo = @rust_resolve_mutex.synchronize { @rust_resolve_memo.has_key?(key) ? {@rust_resolve_memo[key]} : nil }
      return memo[0] if memo
      found = resolve_rust_ref(ref, from, kind, Set(String).new)
      @rust_resolve_mutex.synchronize { @rust_resolve_memo[key] = found }
      found
    end

    # Bound on the `(file, name)` steps one resolution may take; a cyclic
    # re-export graph (`pub use super::*` both ways) visits each step once.
    RUST_RESOLVE_MAX_STEPS = 512

    private def resolve_rust_ref(ref : String, from : String, kind : RustItemKind,
                                 visited : Set(String)) : Tuple(String, String)?
      return unless visit?(visited, "#{from}\0#{ref}")
      parts = ref.gsub(/\s+/, "").lchop("::").split("::").reject(&.empty?).map(&.lchop("r#"))
      return if parts.empty?
      imports = rust_imports(from)
      if parts.size == 1
        leaf = parts[0]
        return {from, leaf} if rust_defines?(kind, from, leaf)
        if (full = imports.names[leaf]?) && full != leaf
          return resolve_rust_path(full.split("::"), from, kind, visited)
        end
        imports.globs.each do |glob|
          if found = resolve_rust_path(glob.split("::") + [leaf], from, kind, visited)
            return found
          end
        end
        return
      end
      if !RUST_PATH_ROOTS.includes?(parts[0]) && (full = imports.names[parts[0]]?)
        parts = full.split("::") + parts[1..]
      end
      resolve_rust_path(parts, from, kind, visited)
    end

    private def visit?(visited : Set(String), key : String) : Bool
      return false if visited.size >= RUST_RESOLVE_MAX_STEPS
      visited.add?(key)
    end

    RUST_PATH_ROOTS = {"crate", "self", "super"}

    private def resolve_rust_path(parts : Array(String), from : String, kind : RustItemKind,
                                  visited : Set(String)) : Tuple(String, String)?
      parts = parts.map(&.lchop("r#"))
      return if parts.size < 2
      rest = parts.dup
      head = rest.shift
      module_file = case head
                    when "crate" then rust_crate_root_of(from)
                    when "self"  then from
                    when "super" then rust_parent_module(from)
                    else              rust_child_module(from, head) || rust_crate_roots[0]["#{crate_scope_for(from)}\0#{head}"]?
                    end
      return unless module_file
      while rest.first? == "super"
        rest.shift
        module_file = rust_parent_module(module_file) || return
      end
      leaf = rest.pop? || return
      rest.each do |segment|
        module_file = rust_child_module(module_file, segment) || return
      end
      return {module_file, leaf} if rust_defines?(kind, module_file, leaf)
      return unless visit?(visited, "#{module_file}\0#{leaf}")

      # `pub use x::leaf;` / `pub use x::*;` re-exports from that module.
      imports = rust_imports(module_file)
      if imports.pub_names.includes?(leaf) && (full = imports.names[leaf]?)
        if found = resolve_rust_ref(full, module_file, kind, visited)
          return found
        end
      end
      imports.pub_globs.each do |glob|
        if found = resolve_rust_ref("#{glob}::#{leaf}", module_file, kind, visited)
          return found
        end
      end
      nil
    end

    private def rust_imports(file : String) : Noir::RustUseImports::Imports
      cached = @rust_resolve_mutex.synchronize { @rust_imports_by_file[file]? }
      return cached if cached
      imports = Noir::RustUseImports.parse(read_file_content(file))
      @rust_resolve_mutex.synchronize { @rust_imports_by_file[file] ||= imports }
    end

    # Expanded path => scanned path of every `.rs` file in the scan.
    private def rust_rs_files : Hash(String, String)
      @rust_resolve_mutex.synchronize do
        @rust_rs_files ||= get_files_by_extension(".rs").to_h { |f| {Noir::PathScope.expand(f), f} }
      end
    end

    # The directory a module file's child modules live in: `src/` for a crate
    # root or `mod.rs`, `src/foo/` for `src/foo.rs`.
    private def rust_module_dir(file : String) : String
      expanded = Noir::PathScope.expand(file)
      base = File.basename(expanded, ".rs")
      dir = File.dirname(expanded)
      return dir if base == "mod" || rust_crate_root?(expanded)
      File.join(dir, base)
    end

    # `#[path = "…"] mod name;` decides the file when present (relative to
    # the declaring file's directory); else `name.rs` / `name/mod.rs`.
    private def rust_child_module(file : String, name : String) : String?
      if path = rust_imports(file).mod_paths[name]?
        return rust_rs_files[Noir::PathScope.expand(File.join(File.dirname(Noir::PathScope.expand(file)), path))]?
      end
      dir = rust_module_dir(file)
      rust_rs_files[File.join(dir, "#{name}.rs")]? || rust_rs_files[File.join(dir, name, "mod.rs")]?
    end

    private def rust_parent_module(file : String) : String?
      expanded = Noir::PathScope.expand(file)
      return if rust_crate_root?(expanded)
      dir = File.dirname(expanded)
      dir = File.dirname(dir) if File.basename(expanded) == "mod.rs"
      {File.join(dir, "mod.rs"), File.join(dir, "lib.rs"), File.join(dir, "main.rs"), "#{dir}.rs"}.each do |candidate|
        next unless found = rust_rs_files[candidate]?
        return found if rust_module_dir(found) == dir
      end
      nil
    end

    # `src/lib.rs`, `src/main.rs` or a manifest's `[lib] path`.
    private def rust_crate_root?(expanded : String) : Bool
      base = File.basename(expanded)
      ((base == "lib.rs" || base == "main.rs") && File.basename(File.dirname(expanded)) == "src") ||
        rust_crate_roots[1].includes?(expanded)
    end

    # The crate root `crate::` means in `file`: `main.rs` for `main.rs`
    # itself and for modules only `main.rs` declares, else `lib.rs`, else
    # `main.rs`.
    private def rust_crate_root_of(file : String) : String?
      expanded = Noir::PathScope.expand(file)
      return rust_rs_files[expanded]? if File.basename(expanded) == "main.rs" && rust_crate_root?(expanded)
      dir = File.dirname(expanded)
      manifests = cargo_manifest_dirs
      loop do
        if manifests.has_key?(dir)
          src = File.join(dir, "src")
          lib_root = rust_rs_files[File.join(src, "lib.rs")]?
          main_root = rust_rs_files[File.join(src, "main.rs")]?
          if lib_root && main_root && expanded.starts_with?("#{src}/")
            top = expanded[(src.size + 1)..].split('/').first.rchop(".rs")
            return main_root if rust_imports(main_root).mods.includes?(top) && !rust_imports(lib_root).mods.includes?(top)
          end
          return lib_root || main_root
        end
        parent = File.dirname(dir)
        return if parent == dir
        dir = parent
      end
    end

    CARGO_SECTION_RE = /^\s*\[([^\]]+)\]/
    CARGO_KEY_RE     = /^\s*(name|path)\s*=\s*"([^"]+)"/

    # `"<crate scope>\0<crate name>"` => crate root file for every scanned
    # `Cargo.toml` (a crate is named by `[lib] name` and `[package] name`,
    # `-` read as `_`), plus the set of those roots' expanded paths.
    private def rust_crate_roots : Tuple(Hash(String, String), Set(String))
      if cached = @rust_resolve_mutex.synchronize { @rust_crate_roots }
        return cached
      end
      files = rust_rs_files
      roots = {} of String => String
      all_files.each do |manifest|
        next unless File.basename(manifest) == "Cargo.toml"
        content = read_file_content(manifest) rescue next
        dir = Noir::PathScope.normalize_root(File.dirname(manifest))
        section = ""
        names = [] of String
        lib_path = nil.as(String?)
        content.each_line do |line|
          if m = line.match(CARGO_SECTION_RE)
            section = m[1].strip
          elsif (m = line.match(CARGO_KEY_RE)) && (section == "package" || section == "lib")
            if m[1] == "name"
              names << m[2].gsub('-', '_')
            elsif section == "lib"
              lib_path = m[2]
            end
          end
        end
        root = lib_path.try { |p| files[Noir::PathScope.expand(File.join(dir, p))]? } ||
               files[File.join(dir, "src", "lib.rs")]? || files[File.join(dir, "src", "main.rs")]?
        next unless root
        scope = crate_scope_for(manifest)
        names.uniq.each { |name| roots["#{scope}\0#{name}"] ||= root }
      end
      result = {roots, roots.values.map { |f| Noir::PathScope.expand(f) }.to_set}
      @rust_resolve_mutex.synchronize { @rust_crate_roots ||= result }
    end

    # Attach the 1-hop callees of `function`'s body to `endpoint`.
    protected def attach_handler_callees(function : LibTreeSitter::TSNode,
                                         source : String,
                                         path : String,
                                         endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body
      entries = Noir::RustCalleeExtractorTS.callees_in_body(body, source, path)
      attach_rust_callees(endpoint, entries)
    end

    private def candidate_module_paths(current_path : String, module_parts : Array(String)) : Array(String)
      return [] of String if module_parts.empty?

      base_dir, parts = module_base_dir(current_path, module_parts)
      return [] of String if parts.empty?

      module_path = parts.join("/")
      [
        File.join(base_dir, "#{module_path}.rs"),
        File.join(base_dir, module_path, "mod.rs"),
      ]
    end

    private def module_base_dir(current_path : String, module_parts : Array(String)) : Tuple(String, Array(String))
      first = module_parts.first
      rest = module_parts[1..]? || [] of String

      case first
      when "crate"
        {crate_src_dir(current_path), rest}
      when "self"
        {current_module_dir(current_path), rest}
      when "super"
        {File.dirname(current_module_dir(current_path)), rest}
      else
        {current_module_dir(current_path), module_parts}
      end
    end

    private def current_module_dir(current_path : String) : String
      File.dirname(current_path)
    end

    private def crate_src_dir(current_path : String) : String
      marker = "/src/"
      if idx = current_path.rindex(marker)
        current_path[0, idx + marker.size - 1]
      else
        File.dirname(current_path)
      end
    end

    # Canonical single module a `.rs` file is referred to by. A plain
    # `foo.rs` is module `foo`; `foo/mod.rs` is module `foo`. A crate root
    # (`src/main.rs` / `src/lib.rs`) has no module name of its own, so we key
    # it by the crate directory — this keeps the identically named
    # `examples/<x>/src/main.rs` roots of a framework example monorepo apart
    # instead of collapsing them all to a shared `src` pseudo-module.
    private def primary_module(path : String) : String
      base = File.basename(path, ".rs")
      dir = File.dirname(path)
      case base
      when "mod"
        File.basename(dir)
      when "lib", "main"
        parent = File.basename(dir)
        parent == "src" ? File.basename(File.dirname(dir)) : parent
      else
        base
      end
    end

    # Byte range + name of every fn, for mapping a route node back to the
    # builder fn that encloses it.
    private def build_fn_ranges(root : LibTreeSitter::TSNode, source : String) : Array(Tuple(Int32, Int32, String))
      ranges = [] of Tuple(Int32, Int32, String)
      walk(root) do |n|
        next unless Noir::TreeSitter.node_type(n) == "function_item"
        name_node = Noir::TreeSitter.field(n, "name")
        next unless name_node
        s = LibTreeSitter.ts_node_start_byte(n).to_i
        e = LibTreeSitter.ts_node_end_byte(n).to_i
        ranges << {s, e, Noir::TreeSitter.node_text(name_node, source)}
      end
      ranges
    end
  end
end
