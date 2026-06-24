require "../models/endpoint"
require "./callee_extractor_base"

# Shared structural helper for the Zig framework analyzers (jetzig, zap,
# httpz, tokamak). Zig has no vendored tree-sitter grammar in noir, so the
# analyzers lean on this hand-rolled miniparser for two jobs:
#
#   * `function_table` / `function_bodies` — index every `fn name(...) { … }`
#     in a source file so a route whose handler lives in a named function
#     (httpz `router.get("/x", getUser, .{})`, tokamak `.get("/", hello)`)
#     can resolve that handler's body for callee extraction.
#   * `callees_for_body` — pull the 1-hop function calls out of a handler
#     body, used by `--include-callee` and `--ai-context`.
#
# The scanners blank out comments and string/char literals first
# (`strip_non_code`) so a call-shaped token inside a doc-string or a `//`
# comment is never surfaced as a phantom callee, and they address the
# source through an `Array(Char)` (O(1) indexing) so a single non-ASCII byte
# anywhere in the file can't turn the per-character loops into O(n²).
module Noir::ZigCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  alias FunctionBody = NamedTuple(body: String, path: String, start_line: Int32)
  alias FunctionInfo = NamedTuple(name: String, body: String, start_line: Int32, open: Int32, close: Int32)

  # Zig keywords that are followed by `(` in normal code (`if (…)`,
  # `while (…)`, `switch (…)`, `catch (…)`) and would otherwise be reported
  # as callees. `fn`/`return`/`try` etc. never precede a call paren directly
  # but are kept here for clarity.
  KEYWORDS = Set{
    "addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm",
    "async", "await", "break", "callconv", "catch", "comptime", "const",
    "continue", "defer", "else", "enum", "errdefer", "error", "export",
    "extern", "fn", "for", "if", "inline", "noalias", "noinline", "nosuspend",
    "opaque", "or", "orelse", "packed", "pub", "resume", "return",
    "linksection", "struct", "suspend", "switch", "test", "threadlocal",
    "try", "union", "unreachable", "usingnamespace", "var", "volatile",
    "while",
  }

  # Receiver roots whose calls are pure noise for endpoint review context.
  # `std.*` (std.debug.print, std.mem.eql, std.fmt.*) appears in nearly
  # every handler and drowns the meaningful callees.
  NOISE_ROOTS = Set{"std"}

  # A `.zig` file that belongs to a *vendored copy of a framework* checked into
  # the source tree (`zig-pkg/zap/…`, `src/deps/tokamak/…`) rather than to the
  # application. Such trees ship the framework's own tests and examples
  # (`zap/src/tests/test_auth.zig`'s `.path = "/test"`, `tokamak/example/`'s
  # `@"GET /:name"`), whose route literals would otherwise surface as phantom
  # app endpoints. The standard fetched-dependency cache (`.zig-cache`) is
  # already pruned upstream; this matches the manual-vendoring layouts —
  # a vendor directory immediately followed by a framework package directory.
  VENDORED_FRAMEWORK_RE = %r{/(?:deps|dep|lib|libs|vendor|vendored|pkg|pkgs|zig-pkg|packages|third_party|third-party|modules|subprojects|external|\.deps)/(?:zap|httpz|http\.zig|tokamak|jetzig|zmpl|zmd)/}

  def vendored_framework_path?(path : String) : Bool
    !VENDORED_FRAMEWORK_RE.match(path.gsub('\\', '/')).nil?
  end

  # `test { … }` / `test "name" { … }` block opener. Route registrations inside
  # a test block are unit-test fixtures — and, in a framework's own source
  # vendored as a loose file (`modules/httpz.zig`, `modules/router.zig`), its
  # self-tests — never runtime endpoints.
  TEST_BLOCK_RE = /(?:^|[^A-Za-z0-9_.])test\s*(?:"(?:[^"\\]|\\.)*"\s*)?\{/

  # Byte ranges of test blocks, brace-matched on the string-blanked source so a
  # `{`/`}` inside a literal can't throw the matching off. `in_test_block?`
  # then lets an analyzer drop a route whose registration sits inside one.
  def test_block_ranges(stripped : String) : Array(Tuple(Int32, Int32))
    chars = stripped.chars
    ranges = [] of Tuple(Int32, Int32)
    stripped.scan(TEST_BLOCK_RE) do |m|
      brace = (m.end(0) || 0) - 1
      close = find_matching(chars, brace, '{', '}')
      next if close.nil?
      ranges << {m.begin(0) || 0, close}
    end
    ranges
  end

  def in_test_block?(offset : Int32, ranges : Array(Tuple(Int32, Int32))) : Bool
    ranges.any? { |r| offset > r[0] && offset < r[1] }
  end

  # A call expression: an optional `@` (builtin) + identifier, then any number
  # of `.identifier` accessors, immediately followed by `(`. The lookbehind
  # stops the match from starting in the middle of an identifier or chain, so
  # `foo.bar(` yields `foo.bar` once, not also `bar`.
  CALL_REGEX = /(?<![A-Za-z0-9_.@])(@?[A-Za-z_][A-Za-z0-9_]*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*\(/

  # `(?:pub )? (modifiers)* fn name (` — captures the function name. The
  # `extern "C"` calling-convention string is already blanked by
  # `strip_non_code`, so only the keyword spacing has to be tolerated.
  FUNCTION_REGEX = /(?:^|[^A-Za-z0-9_.])fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/

  # ---- public entry points (String overloads) -----------------------------

  def strip_non_code(source : String) : String
    String.build { |io| strip_non_code(source.chars).each { |c| io << c } }
  end

  # Like `strip_non_code` but keeps the contents of double-quoted string
  # literals — route paths live inside `"…"`, so the framework analyzers scan
  # this form to read the URL while still ignoring routes that sit in a
  # comment, a `\\` multiline doc-string, or a char literal.
  def strip_comments(source : String) : String
    String.build { |io| strip_comments(source.chars).each { |c| io << c } }
  end

  def function_table(source : String, file_path : String) : Array(FunctionInfo)
    chars = source.chars
    stripped = strip_non_code(chars)
    stripped_str = String.build { |io| stripped.each { |c| io << c } }
    table = [] of FunctionInfo

    stripped_str.scan(FUNCTION_REGEX) do |match|
      name = match[1]
      paren = match.end(0)
      next if paren.nil?
      open_paren = paren - 1
      close_paren = find_matching(stripped, open_paren, '(', ')')
      next if close_paren.nil?

      brace = next_body_brace(stripped, close_paren + 1)
      next if brace.nil?
      close_brace = find_matching(stripped, brace, '{', '}')
      next if close_brace.nil?

      body = slice(stripped, brace + 1, close_brace)
      table << {
        name:       name,
        body:       body,
        start_line: line_at(stripped, brace),
        open:       brace,
        close:      close_brace,
      }
    end

    table
  end

  # Convenience map keyed by simple function name. When two functions share a
  # name (e.g. several zap endpoint structs each defining `get`) the first
  # wins; callers that need struct scoping should filter `function_table`
  # by offset instead.
  def function_bodies(source : String, file_path : String) : Hash(String, FunctionBody)
    bodies = {} of String => FunctionBody
    function_table(source, file_path).each do |info|
      next if bodies.has_key?(info[:name])
      bodies[info[:name]] = {body: info[:body], path: file_path, start_line: info[:start_line]}
    end
    bodies
  end

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    seen = Set(String).new

    # Blank comments/strings so a call-shaped token inside them is never
    # surfaced. Idempotent on the already-stripped bodies the analyzers pass
    # in (spaces stay spaces, newlines and length are preserved so line
    # math is unaffected).
    body = strip_non_code(body)

    body.scan(CALL_REGEX) do |match|
      raw = match[1]
      name = raw.gsub(/\s+/, "")
      offset = match.begin(0) || 0
      next unless callable?(name)
      next if seen.includes?(name)

      seen << name
      entries << {name, file_path, start_line + newlines_before(body, offset)}
    end

    entries
  end

  # ---- filtering -----------------------------------------------------------

  private def callable?(name : String) : Bool
    return false if name.empty?
    return false if name.starts_with?('@') # builtins (@import, @field, …)
    root = name.includes?('.') ? name.split('.', 2).first : name
    return false if KEYWORDS.includes?(root)
    return false if NOISE_ROOTS.includes?(root)
    # A bare keyword call like `if(` (no chain) is filtered above via root;
    # a chained access whose first segment is a keyword is unusual but the
    # root check already covers it.
    true
  end

  # ---- structural primitives (Array(Char), O(1) indexing) ------------------

  def strip_non_code(chars : Array(Char)) : Array(Char)
    out = Array(Char).new(chars.size)
    i = 0
    n = chars.size

    while i < n
      c = chars[i]

      # Line comment: `// …` and Zig doc comments `///` / `//!`.
      if c == '/' && i + 1 < n && chars[i + 1] == '/'
        while i < n && chars[i] != '\n'
          out << ' '
          i += 1
        end
        next
      end

      # Multiline string literal: a `\\` token runs to end of line. Checked
      # before the char/string branches so a `//` or quote inside it can't
      # re-open a comment or literal.
      if c == '\\' && i + 1 < n && chars[i + 1] == '\\'
        while i < n && chars[i] != '\n'
          out << ' '
          i += 1
        end
        next
      end

      # Character literal: `'a'`, `'\n'`, `'\''`.
      if c == '\''
        out << ' '
        i += 1
        while i < n && chars[i] != '\''
          if chars[i] == '\\' && i + 1 < n
            out << ' '
            out << ' '
            i += 2
            next
          end
          out << ' '
          i += 1
        end
        if i < n
          out << ' '
          i += 1
        end
        next
      end

      # Double-quoted string literal: `"…"` with `\"` escapes.
      if c == '"'
        out << ' '
        i += 1
        while i < n && chars[i] != '"'
          if chars[i] == '\\' && i + 1 < n
            out << ' '
            out << ' '
            i += 2
            next
          end
          out << ' '
          i += 1
        end
        if i < n
          out << ' '
          i += 1
        end
        next
      end

      out << c
      i += 1
    end

    out
  end

  def strip_comments(chars : Array(Char)) : Array(Char)
    out = Array(Char).new(chars.size)
    i = 0
    n = chars.size

    while i < n
      c = chars[i]

      # Line / doc comments.
      if c == '/' && i + 1 < n && chars[i + 1] == '/'
        while i < n && chars[i] != '\n'
          out << ' '
          i += 1
        end
        next
      end

      # Multiline string literal (`\\ …` to EOL) — blanked so a route-shaped
      # token inside a doc-string isn't surfaced.
      if c == '\\' && i + 1 < n && chars[i + 1] == '\\'
        while i < n && chars[i] != '\n'
          out << ' '
          i += 1
        end
        next
      end

      # Char literal — blanked.
      if c == '\''
        out << ' '
        i += 1
        while i < n && chars[i] != '\''
          if chars[i] == '\\' && i + 1 < n
            out << ' '
            out << ' '
            i += 2
            next
          end
          out << ' '
          i += 1
        end
        if i < n
          out << ' '
          i += 1
        end
        next
      end

      # Double-quoted string literal — contents PRESERVED.
      if c == '"'
        out << c
        i += 1
        while i < n && chars[i] != '"'
          if chars[i] == '\\' && i + 1 < n
            out << chars[i]
            out << chars[i + 1]
            i += 2
            next
          end
          out << chars[i]
          i += 1
        end
        if i < n
          out << chars[i]
          i += 1
        end
        next
      end

      out << c
      i += 1
    end

    out
  end

  # Find the index of the delimiter matching the opener at `open_index`.
  # Returns nil on imbalance. Operates on the already-stripped char array so
  # braces inside strings/comments are gone.
  def find_matching(chars : Array(Char), open_index : Int32, open : Char, close : Char) : Int32?
    depth = 0
    i = open_index
    n = chars.size
    while i < n
      ch = chars[i]
      if ch == open
        depth += 1
      elsif ch == close
        depth -= 1
        return i if depth == 0
      end
      i += 1
    end
    nil
  end

  # The first `{` at or after `from` that opens a function body. An anonymous
  # struct/enum/union/error return type can carry its own `{` before the body
  # brace; skip past it so we land on the real body opener.
  private def next_body_brace(chars : Array(Char), from : Int32) : Int32?
    i = from
    n = chars.size
    while i < n
      ch = chars[i]
      if ch == '{'
        if container_keyword_before?(chars, i)
          inner = find_matching(chars, i, '{', '}')
          return if inner.nil?
          i = inner + 1
          next
        end
        return i
      end
      # A `;` before any `{` means this was a declaration/prototype, not a
      # definition with a body.
      return if ch == ';'
      i += 1
    end
    nil
  end

  private def container_keyword_before?(chars : Array(Char), brace_index : Int32) : Bool
    j = brace_index - 1
    while j >= 0 && chars[j].whitespace?
      j -= 1
    end
    return false if j < 0
    word_end = j + 1
    while j >= 0 && (chars[j].ascii_alphanumeric? || chars[j] == '_')
      j -= 1
    end
    word = slice(chars, j + 1, word_end)
    word == "struct" || word == "enum" || word == "union" || word == "opaque" || word == "error"
  end

  private def slice(chars : Array(Char), start : Int32, stop : Int32) : String
    return "" if start >= stop
    String.build do |io|
      idx = start
      while idx < stop && idx < chars.size
        io << chars[idx]
        idx += 1
      end
    end
  end

  def line_at(chars : Array(Char), offset : Int32) : Int32
    count = 1
    i = 0
    limit = offset > chars.size ? chars.size : offset
    while i < limit
      count += 1 if chars[i] == '\n'
      i += 1
    end
    count
  end

  private def newlines_before(text : String, offset : Int32) : Int32
    count = 0
    i = 0
    text.each_char do |ch|
      break if i >= offset
      count += 1 if ch == '\n'
      i += 1
    end
    count
  end
end
