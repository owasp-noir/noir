# Crystal bindings for tree-sitter.
#
# Linked against the system-provided libtree-sitter runtime plus per-grammar
# object files that we vendor under `grammars/<lang>/`. Each grammar ships a
# large auto-generated `parser.c` and a small hand-written `scanner.c`.
#
# The ldflags backtick command auto-compiles each grammar when its source
# files are newer than the corresponding `.o`, mirroring the pattern used in
# sibling project `hwaro/src/ext/stb_bindings.cr`.
#
# Upstream versions currently vendored:
#   tree-sitter-python  v0.23.6

require "../../miniparsers/extraction_result_cache"

@[Link(ldflags: "`sh #{__DIR__}/build.sh`")]
lib LibTreeSitter
  # ----- Opaque types -----
  type TSParser = Void*
  type TSTree = Void*
  type TSLanguage = Void*

  # ----- Structs exposed by api.h -----
  struct TSPoint
    row : LibC::UInt
    column : LibC::UInt
  end

  struct TSNode
    context : LibC::UInt[4]
    id : Void*
    tree : Void*
  end

  # ----- Parser lifecycle -----
  fun ts_parser_new : TSParser
  fun ts_parser_delete(parser : TSParser)
  fun ts_parser_set_language(parser : TSParser, language : TSLanguage) : Bool
  fun ts_parser_parse_string(parser : TSParser, old_tree : TSTree, string : LibC::Char*, length : LibC::UInt) : TSTree
  fun ts_parser_set_timeout_micros(parser : TSParser, timeout_micros : UInt64)
  fun ts_parser_reset(parser : TSParser)

  # ----- Tree / node -----
  fun ts_tree_delete(tree : TSTree)
  fun ts_tree_root_node(tree : TSTree) : TSNode
  fun ts_node_string(node : TSNode) : LibC::Char*
  fun ts_node_type(node : TSNode) : LibC::Char*
  fun ts_node_child_count(node : TSNode) : LibC::UInt
  fun ts_node_named_child_count(node : TSNode) : LibC::UInt
  fun ts_node_named_child(node : TSNode, index : LibC::UInt) : TSNode
  fun ts_node_child(node : TSNode, index : LibC::UInt) : TSNode
  fun ts_node_child_by_field_name(node : TSNode, name : LibC::Char*, name_length : LibC::UInt) : TSNode
  fun ts_node_start_byte(node : TSNode) : LibC::UInt
  fun ts_node_end_byte(node : TSNode) : LibC::UInt
  fun ts_node_start_point(node : TSNode) : TSPoint
  fun ts_node_end_point(node : TSNode) : TSPoint
  fun ts_node_is_null(node : TSNode) : Bool
  fun ts_node_is_named(node : TSNode) : Bool

  # ----- Tree cursor -----
  # Visits children in O(1) amortised per step (goto_next_sibling),
  # versus `ts_node_named_child(node, i)` which re-walks the sibling
  # list from the start on every call (O(index)). Layout mirrors
  # `TSTreeCursor` in api.h exactly: {tree, id, context[3]}.
  struct TSTreeCursor
    tree : Void*
    id : Void*
    context : LibC::UInt[3]
  end

  fun ts_tree_cursor_new(node : TSNode) : TSTreeCursor
  fun ts_tree_cursor_delete(cursor : TSTreeCursor*)
  fun ts_tree_cursor_current_node(cursor : TSTreeCursor*) : TSNode
  fun ts_tree_cursor_goto_first_child(cursor : TSTreeCursor*) : Bool
  fun ts_tree_cursor_goto_next_sibling(cursor : TSTreeCursor*) : Bool

  # ----- Grammars (linked from vendored parser.o) -----
  fun tree_sitter_python : TSLanguage
  fun tree_sitter_go : TSLanguage
  fun tree_sitter_java : TSLanguage
  fun tree_sitter_kotlin : TSLanguage
  fun tree_sitter_javascript : TSLanguage
  fun tree_sitter_rust : TSLanguage
end

# Thin high-level facade. Keeps tree lifetime tied to an object so callers
# don't have to think about `ts_tree_delete`.
module Noir::TreeSitter
  # Recursion guard for AST walkers. Crystal's default fiber stack
  # is generous (~8 MB) but a malicious source file with deeply
  # nested syntax — `(((((((...)))))))` chains, deeply nested
  # object literals, recursive template expressions — could
  # cascade through a custom walker until the stack runs out. Real
  # production code rarely nests beyond ~100 levels, so 1024 is
  # comfortably above legitimate input and well below the stack
  # ceiling.
  MAX_AST_DEPTH = 1024

  # Per-language pool of idle parsers. Allocating a tree-sitter parser
  # plus binding a language on every `parse` is cheap individually but
  # adds up across the tens of thousands of files a monorepo scan
  # touches — every Python/Go/Java/Kotlin/JS/Rust analyzer reuses the
  # same grammar over and over. The pool keeps freshly-released parsers
  # alive so the next call skips both `ts_parser_new` and
  # `ts_parser_set_language`.
  #
  # tree-sitter parsers are not safe for concurrent use, so each fiber
  # checks one out for the duration of a `parse` call and returns it
  # when the block exits. The pool itself is mutex-guarded so the
  # checkout/checkin pair is fiber-safe under the MT runtime as well.
  @@parser_pool = Hash(UInt64, Array(LibTreeSitter::TSParser)).new
  @@parser_pool_mutex = Mutex.new

  private def self.checkout_parser(language : LibTreeSitter::TSLanguage) : LibTreeSitter::TSParser
    key = language.address
    @@parser_pool_mutex.synchronize do
      if bucket = @@parser_pool[key]?
        unless bucket.empty?
          return bucket.pop
        end
      end
    end

    parser = LibTreeSitter.ts_parser_new
    raise "ts_parser_new returned null" if parser.null?
    unless LibTreeSitter.ts_parser_set_language(parser, language)
      LibTreeSitter.ts_parser_delete(parser)
      raise "ts_parser_set_language failed (ABI mismatch?)"
    end
    parser
  end

  private def self.checkin_parser(language : LibTreeSitter::TSLanguage, parser : LibTreeSitter::TSParser)
    key = language.address
    @@parser_pool_mutex.synchronize do
      bucket = @@parser_pool[key] ||= [] of LibTreeSitter::TSParser
      bucket << parser
    end
  end

  # Idle parser count for a given language. Exposed for tests and
  # diagnostics; not part of the public API contract.
  def self.parser_pool_size(language : LibTreeSitter::TSLanguage) : Int32
    @@parser_pool_mutex.synchronize do
      (@@parser_pool[language.address]? || [] of LibTreeSitter::TSParser).size
    end
  end

  # Wall-clock ceiling for a single `ts_parser_parse_string` call.
  #
  # tree-sitter's error recovery is quadratic on badly-malformed input: a
  # 200 KB single line of unterminated string literals in a `.go` file
  # spends minutes inside `ts_parser__recover` before returning. Nothing
  # in noir can interrupt that — the parse is one blocking C call, so the
  # scan simply stops, with no output and no way to tell which file did
  # it. Source files are capped at `MediaFilter::MAX_FILE_SIZE` (10 MB) —
  # the larger `MAX_SPEC_FILE_SIZE` covers only specification documents,
  # which no vendored grammar parses — and a well-formed file that size
  # parses in well under a second, so ten
  # seconds is ~100x headroom over any legitimate input while still
  # bounding the pathological case.
  #
  # On expiry the parse returns null and `parse` raises, which the
  # per-file rescue in `parallel_analyze` / `scan_files` logs at debug —
  # one file dropped instead of the whole run.
  # Writable so a spec can force the expiry path deterministically — a
  # sub-millisecond ceiling times out on any non-trivial source, where
  # reproducing a real 10 s timeout would need a pathological fixture and
  # ten seconds of suite time. Nothing in a scan writes it: the value is
  # read once per parse and comes from `NOIR_PARSE_TIMEOUT_MS`.
  class_property parse_timeout_micros : UInt64 = timeout_micros_from_env(ENV["NOIR_PARSE_TIMEOUT_MS"]?)

  # Milliseconds to microseconds, clamped so an absurd value means "effectively
  # no limit" instead of an OverflowError that aborts every command at startup.
  def self.timeout_micros_from_env(raw : String?) : UInt64
    ms = raw.try(&.strip.to_u64?)
    Math.min(ms && ms > 0 ? ms : 10_000_u64, UInt64::MAX // 1000_u64) * 1000_u64
  end

  # Sources that already failed to parse, keyed by content fingerprint and
  # grammar.
  #
  # `parse_timeout_micros` bounds ONE `ts_parser_parse_string` call, but a
  # file is offered to every analyzer of its language, and each one parses it
  # independently — nine Rust analyzers each burn the full ceiling on the same
  # unparsable `.rs` file, so a 10 s bound costs 90 s. The verdict is a pure
  # function of (content, grammar), so remembering it turns that back into one
  # ceiling per file. A timeout is wall-clock and so not strictly
  # deterministic; that is the point — re-running a parse we already know
  # takes longer than the ceiling cannot succeed in less time on the second
  # try, it can only cost the ceiling again.
  #
  # Keyed on content rather than path because `parse` never sees a path, and
  # content is the better key anyway: the `CodeLocator` cache hands the same
  # string to sibling analyzers, and two paths holding identical bytes parse
  # identically.
  PARSE_FAILURE_MAX_ENTRIES = 4096

  @@parse_failures = Hash(UInt64, Bool).new
  @@parse_failure_mutex = Mutex.new

  # A second scan in the same process (diff mode, library use) gets a clean
  # slate, like every other content-keyed memo in the tree.
  Noir::ExtractionResultCache.register_clearer do
    @@parse_failure_mutex.synchronize { @@parse_failures.clear }
  end

  private def self.parse_failure_key(source : String, language : LibTreeSitter::TSLanguage) : UInt64
    Noir::ExtractionResultCache.source_fingerprint(source) &+
      language.address &* 0xd6e8feb86659fd93_u64
  end

  # Parses `source` with the given `language` and yields the root
  # `LibTreeSitter::TSNode`. The parser is checked out from a per-language
  # pool and returned when the block exits; the tree is freed in the
  # same `ensure`.
  def self.parse(source : String, language : LibTreeSitter::TSLanguage, &)
    failure_key = parse_failure_key(source, language)
    # Checked before `checkout_parser` so a known-bad file does not even
    # occupy a pool slot the other analyzers are waiting on.
    if @@parse_failure_mutex.synchronize { @@parse_failures.has_key?(failure_key) }
      raise "tree-sitter parse skipped: this source already failed to parse with this grammar"
    end

    parser = checkout_parser(language)
    begin
      timeout = parse_timeout_micros
      LibTreeSitter.ts_parser_set_timeout_micros(parser, timeout)
      tree = LibTreeSitter.ts_parser_parse_string(parser, Pointer(Void).null.as(LibTreeSitter::TSTree), source.to_unsafe, source.bytesize.to_u32)
      if tree.null?
        # A halted parser holds the partial parse so the next call can
        # resume it. We never resume — the parser goes straight back to
        # the shared pool — so reset it, or the next unrelated file
        # inherits this one's state.
        LibTreeSitter.ts_parser_reset(parser)
        @@parse_failure_mutex.synchronize do
          Noir::ExtractionResultCache.store_capped(
            @@parse_failures, failure_key, true, PARSE_FAILURE_MAX_ENTRIES
          )
        end
        raise "ts_parser_parse_string returned null (timed out after #{timeout // 1000}ms, or out of memory)"
      end
      begin
        yield LibTreeSitter.ts_tree_root_node(tree)
      ensure
        LibTreeSitter.ts_tree_delete(tree)
      end
    ensure
      checkin_parser(language, parser)
    end
  end

  # Parses `source` with the Python grammar and yields the root node.
  def self.parse_python(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_python) { |root| yield root }
  end

  # Parses `source` with the Go grammar and yields the root node.
  def self.parse_go(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_go) { |root| yield root }
  end

  # Parses `source` with the Java grammar and yields the root node.
  def self.parse_java(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_java) { |root| yield root }
  end

  # Parses `source` with the Kotlin grammar and yields the root node.
  def self.parse_kotlin(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_kotlin) { |root| yield root }
  end

  # Parses `source` with the JavaScript grammar and yields the
  # root node. Covers `.js` / `.mjs` / `.cjs` files; the JSX
  # superset is recognised too — JSX-bearing TypeScript needs
  # `parse_typescript` (not yet vendored).
  def self.parse_javascript(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_javascript) { |root| yield root }
  end

  # Parses `source` with the Rust grammar and yields the root node.
  # Covers `.rs` files. Used by the Rust framework analyzers
  # (axum, actix-web, rocket, …) and the Rust callee extractor.
  def self.parse_rust(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_rust) { |root| yield root }
  end

  # --- Small helpers used by extractors. Kept here so callers don't
  # have to touch LibTreeSitter directly. ---

  def self.node_type(node : LibTreeSitter::TSNode) : String
    String.new(LibTreeSitter.ts_node_type(node))
  end

  def self.node_text(node : LibTreeSitter::TSNode, source : String) : String
    sb = LibTreeSitter.ts_node_start_byte(node).to_i
    eb = LibTreeSitter.ts_node_end_byte(node).to_i
    source.byte_slice(sb, eb - sb)
  end

  def self.node_start_row(node : LibTreeSitter::TSNode) : Int32
    LibTreeSitter.ts_node_start_point(node).row.to_i
  end

  def self.node_end_row(node : LibTreeSitter::TSNode) : Int32
    LibTreeSitter.ts_node_end_point(node).row.to_i
  end

  def self.field(node : LibTreeSitter::TSNode, name : String) : LibTreeSitter::TSNode?
    child = LibTreeSitter.ts_node_child_by_field_name(node, name.to_unsafe, name.bytesize.to_u32)
    LibTreeSitter.ts_node_is_null(child) ? nil : child
  end

  def self.first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    return if LibTreeSitter.ts_node_named_child_count(node) == 0
    LibTreeSitter.ts_node_named_child(node, 0_u32)
  end

  # A string literal's `string_fragment` text, or its raw text minus the
  # surrounding double quotes when the grammar exposes no fragments.
  def self.decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
    buf = String.build do |io|
      each_named_child(node) do |child|
        io << node_text(child, source) if node_type(child) == "string_fragment"
      end
    end
    return buf unless buf.empty?
    raw = node_text(node, source)
    raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"') ? raw[1..-2] : raw
  end

  # Above this many named children, switch from indexed access to a
  # tree cursor. `ts_node_named_child(node, i)` is O(i) (it re-walks the
  # sibling list each call), so the indexed loop is O(n^2) in the child
  # count; a cursor walks each child in O(1) amortised but costs one
  # allocation to set up. Small nodes stay on the allocation-free
  # indexed path; wide nodes (large class bodies, `program` roots on big
  # files) take the cursor and avoid the quadratic. Both paths yield the
  # exact same named children in the same order.
  NAMED_CHILD_CURSOR_THRESHOLD = 8

  # Nesting level of the `each_named_child` calls currently on this
  # thread's stack — the descent depth of whatever AST walk is running.
  #
  # Thread-local rather than a plain class variable so two walks running
  # on different threads (the MT runtime, or two analyzers under
  # `parallel_analyze`) cannot corrupt each other's count.
  #
  # Every frame saves the value it found and restores it in an `ensure`,
  # so the counter only ever *over*-estimates: a fiber that suspends
  # mid-walk (a `logger` write inside a walker block) leaves its depth
  # standing, and a walk that starts on the same thread meanwhile is
  # bounded more tightly than it needed to be. That direction is the safe
  # one — it can truncate a pathological walk early, never overrun the
  # stack — and it costs one integer per node instead of per-fiber
  # storage.
  @[ThreadLocal]
  @@walk_depth = 0

  # Iterates named children without allocating an array.
  #
  # Yields nothing once the walk has descended `MAX_AST_DEPTH` levels.
  # Practically every extractor in the tree descends by recursing inside
  # this block, so bounding it here bounds all of them at once: the
  # alternative is threading a `depth` parameter through ~300 hand-rolled
  # walkers and remembering to do it in the next one. A source file with
  # thousands of nested syntactic constructs (`((((...))))`, chained
  # builders, generated code) otherwise recurses until the fiber stack
  # runs out, and a stack overflow is a hard abort — it kills the whole
  # scan, not just the file, and no `rescue` in `parallel_analyze` can
  # catch it. Walkers that thread their own `depth` against
  # `MAX_AST_DEPTH` still cut earlier and more precisely; this is the
  # backstop for the ones that don't.
  #
  # The cursor path lives in a separate `@[NoInline]` method on purpose:
  # these extractors recurse through `each_named_child`'s block, so any
  # local this method reserves (notably the 32-byte `TSTreeCursor`) is
  # paid at every recursion level. Keeping the cursor out of this frame
  # preserves the small original frame for the common narrow-node path,
  # so legitimate deep input stays well inside the stack (guarded by
  # spec/unit_test/miniparser/extractor_recursion_depth_spec).
  def self.each_named_child(node : LibTreeSitter::TSNode, &)
    count = LibTreeSitter.ts_node_named_child_count(node)
    return if count == 0

    depth = @@walk_depth
    return if depth >= MAX_AST_DEPTH
    @@walk_depth = depth + 1

    begin
      if count <= NAMED_CHILD_CURSOR_THRESHOLD
        count.times do |i|
          yield LibTreeSitter.ts_node_named_child(node, i.to_u32)
        end
      else
        each_named_child_via_cursor(node) { |child| yield child }
      end
    ensure
      @@walk_depth = depth
    end
  end

  # Pre-order walk: yields `node`, then every named descendant. Depth is
  # bounded by `each_named_child`.
  def self.walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    block.call(node)
    each_named_child(node) do |child|
      walk(child, &block)
    end
  end

  @[NoInline]
  private def self.each_named_child_via_cursor(node : LibTreeSitter::TSNode, &)
    cursor = LibTreeSitter.ts_tree_cursor_new(node)
    begin
      has_child = LibTreeSitter.ts_tree_cursor_goto_first_child(pointerof(cursor))
      while has_child
        child = LibTreeSitter.ts_tree_cursor_current_node(pointerof(cursor))
        yield child if LibTreeSitter.ts_node_is_named(child)
        has_child = LibTreeSitter.ts_tree_cursor_goto_next_sibling(pointerof(cursor))
      end
    ensure
      LibTreeSitter.ts_tree_cursor_delete(pointerof(cursor))
    end
  end
end
