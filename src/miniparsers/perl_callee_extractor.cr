require "../models/endpoint"
require "../analyzer/analyzers/perl/perl_helper"
require "./callee_extractor_base"

module Noir::PerlCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  alias SubBody = NamedTuple(body: String, path: String, start_line: Int32)

  RESERVED = Set{
    "and", "cmp", "continue", "do", "else", "elsif", "eq", "eval",
    "for", "foreach", "ge", "given", "gt", "if", "last", "le", "lt",
    "my", "ne", "next", "no", "not", "our", "package", "return", "state",
    "sub", "unless", "until", "use", "when", "while",
    "bless", "caller", "chomp", "chop", "close", "defined", "delete",
    "die", "each", "exists", "grep", "join", "keys", "length", "map",
    "open", "pop", "print", "push", "qw", "q", "qq", "qr", "ref",
    "scalar", "shift", "sort", "split", "sprintf", "undef", "unshift",
    "values", "wantarray", "warn",
  }

  STANDARD_MODULES = Set{
    "Carp", "Data::Dumper", "Encode", "File::Spec", "JSON", "List::Util",
    "Mojo::Base", "Mojolicious::Lite", "strict", "warnings",
  }

  METHOD_CALL_REGEX    = /(\$?[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)\s*->\s*([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])\s*(?:\(|(?=\s*(?:[A-Za-z_$'"]|\{|\[|;|,|\)|\}|$)))/
  QUALIFIED_CALL_REGEX = /(?<![A-Za-z0-9_:])([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)+)\s*(?:\(|(?=\s+(?:[A-Za-z_$'"]|\{|\[)))/
  BARE_CALL_REGEX      = /(?<![A-Za-z0-9_:>$])([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|(?=\s+(?:[A-Za-z_$'"]|\{|\[)))/

  # The structural scanners below address characters by integer index. On a
  # String that is not single-byte-optimizable (i.e. contains any non-ASCII
  # character — an em-dash in a comment is enough), `String#[](Int)` is O(n),
  # so the per-character loops degrade to O(n²) and can hang the scan on a
  # large file. Working over an `Array(Char)` keeps every index access O(1)
  # while preserving exact character semantics; the only structural tokens we
  # ever match are ASCII, and substrings are rebuilt from the real characters.

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    stripped = strip_nested_sub_bodies(strip_non_code(body).chars)

    stripped.each_line.with_index do |line, offset|
      scan_line(line, file_path, start_line + offset, entries)
    end

    dedup_entries(entries)
  end

  def controller_action_callees(source : String, file_path : String) : Hash(String, Array(Entry))
    package = package_name(source)
    return {} of String => Array(Entry) unless package
    return {} of String => Array(Entry) unless package.includes?("::Controller::")

    controller = package.split("::Controller::", 2)[1]?
    return {} of String => Array(Entry) unless controller

    bodies = named_sub_bodies(source, file_path)
    actions = {} of String => Array(Entry)
    controller_keys(controller).each do |controller_key|
      bodies.each do |action, body|
        key = "#{controller_key}##{action}"
        actions[key] = callees_for_body(body[:body], body[:path], body[:start_line])
      end
    end

    actions
  end

  def named_sub_bodies(source : String, file_path : String) : Hash(String, SubBody)
    bodies = {} of String => SubBody
    chars = code_chars(source)
    stripped = strip_non_code(chars)

    stripped.scan(/\bsub\s+([A-Za-z_][A-Za-z0-9_]*)\b/) do |match|
      sub_index = match.begin(0) || 0
      next unless sub_keyword_at?(chars, sub_index)
      next unless body = extract_sub_at(chars, sub_index)

      body_text, start_line = body
      bodies[match[1]] ||= {body: body_text, path: file_path, start_line: start_line}
    end

    bodies
  end

  def extract_sub_after(source : String,
                        start_index : Int32,
                        search_limit : Int32 = source.size,
                        body_limit : Int32 = source.size) : Tuple(String, Int32)?
    chars = code_chars(source)
    sub_index = find_keyword(chars, "sub", start_index, search_limit)
    return unless sub_index

    extract_sub_at(chars, sub_index, body_limit)
  end

  # Public String overload kept for callers outside this module.
  def extract_sub_at(source : String,
                     sub_index : Int32,
                     limit : Int32 = source.size) : Tuple(String, Int32)?
    extract_sub_at(code_chars(source), sub_index, limit)
  end

  def extract_sub_at(chars : Array(Char),
                     sub_index : Int32,
                     limit : Int32 = chars.size) : Tuple(String, Int32)?
    return unless sub_keyword_at?(chars, sub_index)

    open_brace = find_char(chars, '{', sub_index, limit)
    return unless open_brace
    close_brace = find_matching_delimiter(chars, open_brace, '{', '}', limit)
    return unless close_brace

    {chars[(open_brace + 1)...close_brace].join, line_number_for(chars, open_brace + 1)}
  end

  # Public String overload kept for callers outside this module.
  def find_matching_delimiter(source : String, open_index : Int32, open_char : Char, close_char : Char,
                              limit : Int32 = source.size) : Int32?
    find_matching_delimiter(code_chars(source), open_index, open_char, close_char, limit)
  end

  def find_matching_delimiter(chars : Array(Char), open_index : Int32, open_char : Char, close_char : Char,
                              limit : Int32 = chars.size) : Int32?
    depth = 0
    index = open_index

    while index < limit && index < chars.size
      char = chars[index]
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif quote_like_start?(chars, index)
        index = skip_quote_like(chars, index, limit)
        next
      elsif char == '"' || char == '\''
        index = skip_short_string(chars, index, limit)
        next
      elsif char == open_char
        depth += 1
      elsif char == close_char
        depth -= 1
        return index if depth == 0
      end

      index += 1
    end

    nil
  end

  # Public String overload kept for callers outside this module.
  def strip_non_code(source : String) : String
    # Fast path: nothing to blank when the source has no comment, short
    # string, quote-like (`q`/`qq`/`qw`/`qr`/`qx`), or heredoc markers.
    # Preserves byte-identical output for the common "already plain code"
    # case used by brace-depth walks.
    heredocs = source.includes?("<<")
    needed = strip_non_code_needed?(source)
    return source unless heredocs || needed

    chars = source.chars
    masked = heredocs ? mask_heredocs(chars) : chars
    # `mask_heredocs` returns the input untouched when the `<<` was a shift,
    # which keeps the byte-identical fast path for plain code.
    return source if !needed && masked.same?(chars)

    strip_non_code(masked)
  end

  # Heredoc bodies are data, not code: their braces would close the enclosing
  # `sub` early and a stray apostrophe would open a "string" that blanks the
  # statements after it. Mask them (and the `<<TAG` token itself) with spaces
  # before any other lexing runs, keeping newlines so every character offset
  # and line number stays identical.
  private def code_chars(source : String) : Array(Char)
    chars = source.chars
    source.includes?("<<") ? mask_heredocs(chars) : chars
  end

  private def mask_heredocs(chars : Array(Char)) : Array(Char)
    # `<<` is far more often a left shift than a heredoc, so the copy is only
    # allocated once a real marker is seen.
    masked = nil.as(Array(Char)?)
    pending = [] of Tuple(String, Bool)
    index = 0
    size = chars.size

    while index < size
      if pending.empty?
        if comment_start?(chars, index)
          index = skip_comment(chars, index, size)
          next
        elsif quote_like_start?(chars, index)
          index = skip_quote_like(chars, index, size)
          next
        elsif chars[index] == '"' || chars[index] == '\''
          index = skip_short_string(chars, index, size)
          next
        end
      elsif chars[index] == '\n'
        # Bodies start on the line after the marker; several heredocs may be
        # opened on one line (`print <<A, <<B;`) and stack in order.
        buffer = masked || chars.dup
        masked = buffer
        cursor = index + 1
        pending.each do |tag, indented|
          cursor = blank_heredoc_body(chars, buffer, cursor, tag, indented)
        end
        pending.clear
        index = cursor
        next
      end

      if marker = heredoc_marker_at(chars, index)
        tag, indented, token_end = marker
        buffer = masked || chars.dup
        masked = buffer
        blank_range(buffer, index, token_end)
        pending << {tag, indented}
        index = token_end
        next
      end

      index += 1
    end

    masked || chars
  end

  # `<<TAG` / `<<'TAG'` / `<<"TAG"` / `<<~TAG`. Perl only reads a bare
  # (unquoted) terminator when it follows `<<` with no space, which is what
  # keeps `$x << 2` and `$x << $bits` reading as a left shift. For the bare
  # form we additionally require that a matching terminator line exists, so a
  # shift by a named constant (`1<<MAX`) is not swallowed as a heredoc.
  private def heredoc_marker_at(chars : Array(Char), index : Int32) : Tuple(String, Bool, Int32)?
    return unless chars[index] == '<' && chars[index + 1]? == '<'

    cursor = index + 2
    indented = false
    if chars[cursor]? == '~'
      indented = true
      cursor += 1
    end

    quote = chars[cursor]?
    if quote == '\'' || quote == '"'
      cursor += 1
      tag_start = cursor
      while (char = chars[cursor]?) && identifier_part?(char)
        cursor += 1
      end
      return if cursor == tag_start
      return unless chars[cursor]? == quote
      return {chars[tag_start...cursor].join, indented, cursor + 1}
    end

    tag_start = cursor
    first = chars[cursor]?
    return unless first && identifier_start?(first)
    while (char = chars[cursor]?) && identifier_part?(char)
      cursor += 1
    end

    tag = chars[tag_start...cursor].join
    return unless indented || heredoc_terminator_ahead?(chars, cursor, tag, indented)
    {tag, indented, cursor}
  end

  private def heredoc_terminator_ahead?(chars : Array(Char), index : Int32, tag : String, indented : Bool) : Bool
    cursor = index
    while cursor < chars.size && chars[cursor] != '\n'
      cursor += 1
    end
    cursor += 1

    while cursor < chars.size
      line_end = cursor
      while line_end < chars.size && chars[line_end] != '\n'
        line_end += 1
      end
      return true if heredoc_terminator?(chars, cursor, line_end, tag, indented)
      cursor = line_end + 1
    end

    false
  end

  # Blanks every line of the body plus the terminator line. An unterminated
  # heredoc blanks to EOF and returns — it never loops.
  private def blank_heredoc_body(chars : Array(Char), masked : Array(Char),
                                 index : Int32, tag : String, indented : Bool) : Int32
    cursor = index

    while cursor < chars.size
      line_end = cursor
      while line_end < chars.size && chars[line_end] != '\n'
        line_end += 1
      end

      terminator = heredoc_terminator?(chars, cursor, line_end, tag, indented)
      blank_range(masked, cursor, line_end)
      cursor = line_end < chars.size ? line_end + 1 : line_end
      return cursor if terminator
    end

    cursor
  end

  private def heredoc_terminator?(chars : Array(Char), line_start : Int32, line_end : Int32,
                                  tag : String, indented : Bool) : Bool
    start_index = line_start
    if indented
      while start_index < line_end && chars[start_index].whitespace?
        start_index += 1
      end
    end

    finish = line_end
    while finish > start_index && chars[finish - 1].whitespace?
      finish -= 1
    end

    return false unless finish - start_index == tag.size

    offset = start_index
    tag.each_char do |char|
      return false unless chars[offset] == char
      offset += 1
    end
    true
  end

  private def blank_range(masked : Array(Char), start_index : Int32, finish_index : Int32)
    index = start_index
    while index < finish_index && index < masked.size
      masked[index] = ' ' unless masked[index] == '\n'
      index += 1
    end
  end

  def strip_non_code(chars : Array(Char)) : String
    stripped = String::Builder.new
    index = 0

    while index < chars.size
      char = chars[index]
      if comment_start?(chars, index)
        finish = skip_comment(chars, index, chars.size)
        append_blanks(stripped, chars, index, finish)
        index = finish
        next
      elsif quote_like_start?(chars, index)
        finish = skip_quote_like(chars, index, chars.size)
        append_string_placeholder(stripped, chars, index, finish)
        index = finish
        next
      elsif char == '"' || char == '\''
        finish = skip_short_string(chars, index, chars.size)
        append_string_placeholder(stripped, chars, index, finish)
        index = finish
        next
      end

      stripped << char
      index += 1
    end

    stripped.to_s
  end

  # Public String overload kept for callers outside this module.
  # Walk characters up to `index` counting newlines — the previous
  # `source[0...limit].count('\n')` allocated a full substring on every
  # call (handler body extraction, named-sub indexing). `index` is a
  # character offset (matches `source.chars` / `String#size` indexing),
  # not a UTF-8 byte offset.
  def line_number_for(source : String, index : Int32) : Int32
    return 1 if index <= 0

    count = 1
    i = 0
    source.each_char do |ch|
      break if i >= index
      count += 1 if ch == '\n'
      i += 1
    end
    count
  end

  def line_number_for(chars : Array(Char), index : Int32) : Int32
    return 1 if index <= 0

    limit = index > chars.size ? chars.size : index
    count = 1
    i = 0
    while i < limit
      count += 1 if chars[i] == '\n'
      i += 1
    end
    count
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    candidates = [] of Tuple(Int32, String)

    line.scan(METHOD_CALL_REGEX) do |match|
      candidates << {match.begin(0) || 0, "#{normalize_receiver(match[1])}.#{match[2]}"}
    end
    scan_candidates(line, QUALIFIED_CALL_REGEX, candidates)
    scan_candidates(line, BARE_CALL_REGEX, candidates)

    candidates.sort_by! { |position, _| position }
    candidates.each do |position, name|
      next if skip_callee?(name)
      next if declaration_name?(line, position)

      entries << {name, file_path, line_number}
    end
  end

  private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
    line.scan(regex) do |match|
      candidates << {match.begin(1) || 0, match[1]}
    end
  end

  private def normalize_receiver(name : String) : String
    normalized = name.starts_with?("$") ? name[1..] : name
    normalized.gsub("::", ".")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    base = name.split('.').last
    return true if RESERVED.includes?(base)
    return true if STANDARD_MODULES.includes?(name)

    false
  end

  private def declaration_name?(line : String, position : Int32) : Bool
    prefix = line[0...position]
    !!prefix.match(/\bsub\s+$/)
  end

  private def strip_nested_sub_bodies(chars : Array(Char)) : String
    stripped = String::Builder.new
    index = 0

    while index < chars.size
      if sub_keyword_at?(chars, index)
        finish = find_matching_sub_end(chars, index) || index + "sub".size
        append_blanks(stripped, chars, index, finish)
        index = finish
        next
      end

      stripped << chars[index]
      index += 1
    end

    stripped.to_s
  end

  private def find_matching_sub_end(chars : Array(Char), sub_index : Int32) : Int32?
    open_brace = find_char(chars, '{', sub_index, chars.size)
    return unless open_brace
    close_brace = find_matching_delimiter(chars, open_brace, '{', '}', chars.size)
    return unless close_brace
    close_brace + 1
  end

  private def package_name(source : String) : String?
    return unless source.includes?("package")
    stripped = strip_non_code(source)
    if match = stripped.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_:]*)\s*;/m)
      match[1]
    end
  end

  # Markers that force a full `strip_non_code` walk. Quote-like ops are
  # matched via the common `q…` spellings; a lone `q` inside an identifier
  # (`require`) is intentionally not enough — the char walk still handles
  # rare `q /foo/` forms if another marker already forced the walk, and
  # pure-code files without quotes/comments skip it entirely.
  private def strip_non_code_needed?(source : String) : Bool
    source.includes?('#') || source.includes?('\'') || source.includes?('"') ||
      source.includes?("qq") || source.includes?("qw") || source.includes?("qr") ||
      source.includes?("qx") || source.includes?("q{") || source.includes?("q(") ||
      source.includes?("q[") || source.includes?("q/") || source.includes?("q!") ||
      source.includes?("q|") || source.includes?("q ") ||
      # `q` accepts any non-word delimiter, e.g. angle-bracket `q<...>`, which
      # the full walker blanks; missing it here let `q<foo(bar)>` slip through
      # the fast path and emit a spurious callee. Cover the remaining common
      # bracket/punctuation delimiters (widening the gate only ever routes
      # more input through the exact walk — it can never drop a callee).
      source.includes?("q<") || source.includes?("q~") ||
      source.includes?("q,") || source.includes?("q:") ||
      source.includes?("q.") || source.includes?("q;")
  end

  private def controller_keys(controller : String) : Array(String)
    keys = Set(String).new
    segments = controller.split("::")
    keys << segments.map(&.downcase).join("/")
    keys << segments.map { |segment| Analyzer::Perl::Helper.underscore(segment) }.join("/")
    keys.to_a
  end

  private def find_keyword(chars : Array(Char), keyword : String, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < chars.size
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif quote_like_start?(chars, index)
        index = skip_quote_like(chars, index, limit)
        next
      elsif chars[index] == '"' || chars[index] == '\''
        index = skip_short_string(chars, index, limit)
        next
      elsif identifier_start?(chars[index])
        token_start = index
        token, index = read_identifier(chars, index, limit)
        return token_start if token == keyword
        next
      end

      index += 1
    end

    nil
  end

  private def find_char(chars : Array(Char), target : Char, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < chars.size
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif quote_like_start?(chars, index)
        index = skip_quote_like(chars, index, limit)
        next
      elsif chars[index] == '"' || chars[index] == '\''
        index = skip_short_string(chars, index, limit)
        next
      end

      return index if chars[index] == target

      index += 1
    end

    nil
  end

  private def sub_keyword_at?(chars : Array(Char), index : Int32) : Bool
    return false unless chars[index]? == 's' && chars[index + 1]? == 'u' && chars[index + 2]? == 'b'
    before = index > 0 ? chars[index - 1] : '\0'
    after_index = index + "sub".size
    after = after_index < chars.size ? chars[after_index] : '\0'
    !identifier_part?(before) && !identifier_part?(after)
  end

  private def read_identifier(chars : Array(Char), index : Int32, limit : Int32) : Tuple(String, Int32)
    cursor = index
    while cursor < limit && cursor < chars.size && identifier_part?(chars[cursor])
      cursor += 1
    end

    {chars[index...cursor].join, cursor}
  end

  private def identifier_start?(char : Char) : Bool
    char.ascii_letter? || char == '_'
  end

  private def identifier_part?(char : Char) : Bool
    char.ascii_alphanumeric? || char == '_'
  end

  private def comment_start?(chars : Array(Char), index : Int32) : Bool
    return false unless chars[index] == '#'
    # `$#array`, `$#{$ref}` and `$#$ref` are the last-index sigil, not a
    # comment. Treating them as one blanked the rest of the line — including
    # the closing brace of a one-line `sub` — and dropped every callee on it.
    !(index > 0 && chars[index - 1] == '$')
  end

  private def skip_comment(chars : Array(Char), index : Int32, limit : Int32) : Int32
    cursor = index
    while cursor < limit && cursor < chars.size && chars[cursor] != '\n'
      cursor += 1
    end
    cursor
  end

  private def quote_like_start?(chars : Array(Char), index : Int32) : Bool
    return false unless index < chars.size
    return false unless chars[index] == 'q'
    return false if index > 0 && identifier_part?(chars[index - 1])

    cursor = index + 1
    if cursor < chars.size && {'q', 'r', 'w', 'x'}.includes?(chars[cursor])
      cursor += 1
    elsif cursor < chars.size && identifier_part?(chars[cursor])
      return false
    end

    while cursor < chars.size && chars[cursor].whitespace?
      cursor += 1
    end
    return false if cursor >= chars.size

    !!quote_close_char(chars[cursor])
  end

  private def skip_quote_like(chars : Array(Char), index : Int32, limit : Int32) : Int32
    cursor = index + 1
    cursor += 1 if cursor < limit && cursor < chars.size && {'q', 'r', 'w', 'x'}.includes?(chars[cursor])
    while cursor < limit && cursor < chars.size && chars[cursor].whitespace?
      cursor += 1
    end
    return index + 1 if cursor >= limit || cursor >= chars.size

    open_char = chars[cursor]
    close_char = quote_close_char(open_char)
    return index + 1 unless close_char

    cursor += 1
    escaped = false
    while cursor < limit && cursor < chars.size
      char = chars[cursor]
      if escaped
        escaped = false
      elsif char == '\\'
        escaped = true
      elsif char == close_char
        return cursor + 1
      end
      cursor += 1
    end

    limit
  end

  private def quote_close_char(open_char : Char) : Char?
    case open_char
    when '('                      then ')'
    when '['                      then ']'
    when '{'                      then '}'
    when '<'                      then '>'
    when '"', '\'', '/', '|', '!' then open_char
    end
  end

  private def skip_short_string(chars : Array(Char), index : Int32, limit : Int32) : Int32
    quote = chars[index]
    cursor = index + 1
    escaped = false

    while cursor < limit && cursor < chars.size
      char = chars[cursor]
      if escaped
        escaped = false
      elsif char == '\\'
        escaped = true
      elsif char == quote
        return cursor + 1
      end
      cursor += 1
    end

    limit
  end

  private def append_blanks(builder : String::Builder, chars : Array(Char), start_index : Int32, finish_index : Int32)
    index = start_index
    while index < finish_index && index < chars.size
      builder << (chars[index] == '\n' ? '\n' : ' ')
      index += 1
    end
  end

  private def append_string_placeholder(builder : String::Builder, chars : Array(Char), start_index : Int32, finish_index : Int32)
    placeholder_written = false
    index = start_index
    while index < finish_index && index < chars.size
      if chars[index] == '\n'
        builder << '\n'
      elsif !placeholder_written
        builder << ' '
        placeholder_written = true
      else
        builder << ' '
      end
      index += 1
    end
  end
end
