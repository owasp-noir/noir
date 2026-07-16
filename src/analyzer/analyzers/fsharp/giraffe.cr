require "../../../models/analyzer"
require "../../../miniparsers/fsharp_callee_extractor"

module Analyzer::Fsharp
  # Giraffe is a functional web framework on top of ASP.NET Core. Routes
  # are HttpHandler values composed via the `>=>` Kleisli operator and
  # collected with `choose [...]`. Common combinators surfaced here:
  #
  #   * `route "/path"`             — exact path match
  #   * `routeCi "/path"`           — case-insensitive variant
  #   * `routex "regex"`            — regex variant (path is reported verbatim)
  #   * `routef "/users/%i/%s"`     — typed parameters
  #   * `subRoute "/prefix" handler` and friends — mount nested routes
  #
  # HTTP method filters (`GET`, `POST`, etc.) appearing on the same
  # textual line as a route are honored; lines without an explicit
  # method default to a fallback set.
  class Giraffe < Analyzer
    HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    FALLBACK_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). Both the stop-line matcher and the
    # per-verb window probes interpolate only fixed patterns, so
    # precompile them once at load time.
    ROUTE_COMBINATOR      = /(?:route(?:Bind|Ci[fx]?|xp?|f)?|subRoute(?:Ci|f)?)\b/
    ROUTE_HANDLER_STOP_RE = /\A(?:(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b.*\b#{ROUTE_COMBINATOR}|#{ROUTE_COMBINATOR})/
    METHOD_WORD_PATTERNS  = HTTP_METHODS.map do |m|
      {m, /\b#{m}\b/}
    end

    # Combinator matchers for the main scan loop below. `\G` (rather than
    # `\A`) anchors each match to the exact byte offset passed to
    # `Regex#match_at_byte_index`, mirroring what `\A` did against a
    # freshly sliced `cleaned[i..]` remainder -- but without the slice.
    SUB_ROUTE_RE   = /\G(subRoute(?:Ci|f)?)\s+"([^"]+)"\s*([\(\[])/
    VERB_CHOOSE_RE = /\G(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*>=>\s*choose\s*\[/
    VERB_LIST_RE   = /\G(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\[/
    ROUTE_BIND_RE  = /\GrouteBind(?:\s*<[^>\n]*>)?\s+"([^"]+)"/
    ROUTEF_RE      = /\G(?:routef|routeCif)\s+"([^"]+)"/
    ROUTE_RE       = /\G(?:routeCix|routexp|routeCi|routex|route)\s+"([^"]+)"/
    ROUTE_CONST_RE = /\G(?:routeCix|routexp|routeCi|routex|route)\s+([A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*)/

    # PCRE2 (Crystal's regex backend) re-validates UTF-8 encoding of the
    # subject on every `match_at_byte_index` call by default -- an
    # O(remaining-length) pass, since our scan loop calls it at every
    # character position that O(n²) rather than O(n). `content` (and
    # `cleaned`, built from it) is always sourced through
    # `Analyzer#read_file_content`, which reads with `invalid: :skip`, so
    # both are guaranteed structurally valid UTF-8 already -- the same
    # invariant `String#scan` in the standard library relies on when it
    # sets this same option after its first match. Confirmed empirically:
    # a 4x-larger synthetic file went from ~16.7s to ~0.014s once this was
    # applied to the combinator matchers below (~1000x).
    NO_UTF_CHECK = Regex::MatchOptions::NO_UTF_CHECK

    # Mapping of routef format specifiers to noir path-param types.
    ROUTEF_PARAM_TYPES = {
      'i' => "int",
      'd' => "int64",
      'b' => "bool",
      'c' => "char",
      's' => "string",
      'f' => "float",
      'O' => "guid",
      'u' => "uint64",
    }

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".fs") || path.ends_with?(".fsx")
        # Skip .NET test conventions: `/tests/` and `/test/`
        # parent dirs, and `*Tests.fs` filenames. Giraffe's own
        # `tests/Giraffe.Tests/*.fs` accounts for ~218 phantom
        # endpoints — full `webApp` HttpHandler trees built only
        # to exercise the routing combinators.
        next if fsharp_test_path?(path)

        content = read_file_content(path)
        process_file(path, content, include_callee)
      end

      @result
    end

    private def fsharp_test_path?(path : String) : Bool
      return true if path.includes?("/tests/")
      return true if path.includes?("/test/")
      base = File.basename(path)
      return true if base.ends_with?("Tests.fs")
      base.ends_with?("Test.fs")
    end

    alias SubRouteScope = NamedTuple(prefix: String, end_pos: Int32, params: Array(Param), method: String?)

    private def process_file(path : String, content : String, include_callee : Bool)
      cleaned = strip_fsharp_comments(content)
      # Address `cleaned` through an `Array(Char)`: integer `String#[](Int)` is
      # O(n) on non-ASCII source (one em-dash defeats single-byte optimization),
      # so the per-character work below — and the literal skip — would be O(n²).
      cleaned_chars = cleaned.chars
      # Byte offset of every char position (plus one past the end), computed
      # once in O(n). Lets the loop below hand `Regex#match_at_byte_index` a
      # ready byte offset for the *current* position instead of re-slicing
      # `cleaned[i..]` on every iteration — that slice copies O(remaining
      # length) bytes each time, so the O(n) scan becomes O(n²) regardless of
      # ASCII content (confirmed: 4x source size measured ~16x scan time).
      byte_offsets = char_byte_offsets(cleaned_chars)
      # Newline positions in `content`, computed once in O(n) so
      # `line_for_offset` below can binary-search instead of re-walking
      # from the start of the file for every emitted route (see its
      # doc comment for the O(n²) this replaces).
      newline_offsets = collect_newline_offsets(content)
      scope_stack = [] of SubRouteScope
      string_constants = collect_string_constants(cleaned)

      i = 0
      while i < cleaned.size
        # Drop sub-route scopes whose closing paren has already passed.
        while !scope_stack.empty? && scope_stack.last[:end_pos] <= i
          scope_stack.pop
        end

        # No route combinator begins with a quote, so a string literal reached
        # here is not part of one. Jump past it in a single step — walking it
        # character by character (each re-slicing `cleaned[i..]`) is O(n²) and
        # hangs the scan on a multi-kilobyte literal.
        if cleaned_chars[i] == '"'
          i = skip_string_literal(cleaned_chars, i)
          next
        end

        byte_i = byte_offsets[i]

        # subRoute / subRouteCi / subRoutef "/prefix" (handler)
        # or the Giraffe 6+ Endpoint Routing form: `subRoute "/prefix" [ ... ]`.
        sub_match = SUB_ROUTE_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if sub_match
          combinator = sub_match[1]
          raw_prefix = sub_match[2]
          opener = sub_match[3]
          match_end = sub_match.end(0)
          if match_end
            open_abs = match_end - 1
            close_pos = opener == "(" ? find_matching_paren(cleaned, open_abs) : find_matching_bracket(cleaned, open_abs)
            if close_pos
              translated_prefix, prefix_params = if combinator == "subRoutef"
                                                   translate_routef(raw_prefix)
                                                 else
                                                   {raw_prefix, [] of Param}
                                                 end
              scope_stack << {
                prefix:  translated_prefix,
                end_pos: close_pos,
                params:  prefix_params,
                method:  nil,
              }
              i = match_end
              next
            end
          end
        end

        # `VERB >=> choose [ ... ]` — an HTTP verb applied to an entire
        # `choose` block. This is the canonical Giraffe idiom (e.g.
        # `GET >=> choose [ route "/" ...; route "/ping" ... ]`), and
        # without it every nested route falls back to the full method
        # set. `\s` spans the line break in the common multi-line layout
        # where the verb sits on its own line above `choose [`.
        verb_choose_match = VERB_CHOOSE_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if verb_choose_match && verb_list_method_context?(cleaned, i)
          verb = verb_choose_match[1]
          match_end = verb_choose_match.end(0)
          if match_end
            open_bracket_abs = match_end - 1
            close_bracket = find_matching_bracket(cleaned, open_bracket_abs)
            if close_bracket
              scope_stack << {
                prefix:  "",
                end_pos: close_bracket,
                params:  [] of Param,
                method:  verb,
              }
              i = match_end
              next
            end
          end
        end

        # Giraffe Endpoint Routing: `GET [ route "/" h; route "/x" h ]`.
        # The verb token wraps a list of routes. When this form is used,
        # the embedded `route` lines do not carry the verb on their own
        # line, so we push a method-only scope until the matching `]`.
        verb_list_match = VERB_LIST_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if verb_list_match && verb_list_method_context?(cleaned, i)
          verb = verb_list_match[1]
          match_end = verb_list_match.end(0)
          if match_end
            open_bracket_abs = match_end - 1
            close_bracket = find_matching_bracket(cleaned, open_bracket_abs)
            if close_bracket
              scope_stack << {
                prefix:  "",
                end_pos: close_bracket,
                params:  [] of Param,
                method:  verb,
              }
              i = match_end
              next
            end
          end
        end

        # routeBind<'T> "/p/{firstName}/{lastName}" — named parameters
        # bound to a record's properties. `{name}` placeholders become
        # `:name` path params. The pattern may also carry trailing regex
        # (e.g. `(/?)`), which is reported verbatim.
        bind_match = ROUTE_BIND_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if bind_match && token_boundary?(cleaned, i)
          path_pattern = bind_match[1]
          match_end = bind_match.end(0)
          emit_route(path, content, cleaned, i, scope_stack, path_pattern, routef: false, include_callee: include_callee, bind: true, newline_offsets: newline_offsets)
          i = match_end || (i + 1)
          next
        end

        # routef / routeCif "/users/%i/%s" — typed format parameters
        # (routeCif is the case-insensitive variant of routef).
        routef_match = ROUTEF_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if routef_match && token_boundary?(cleaned, i)
          path_pattern = routef_match[1]
          match_end = routef_match.end(0)
          emit_route(path, content, cleaned, i, scope_stack, path_pattern, routef: true, include_callee: include_callee, newline_offsets: newline_offsets)
          i = match_end || (i + 1)
          next
        end

        # route / routeCi "/path" exact match, plus the regex variants
        # routex / routeCix / routexp (path reported verbatim). The
        # `routeStartsWith*` prefix guards are intentionally excluded —
        # they filter without defining a complete endpoint.
        route_match = ROUTE_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if route_match && token_boundary?(cleaned, i)
          path_pattern = route_match[1]
          match_end = route_match.end(0)
          emit_route(path, content, cleaned, i, scope_stack, path_pattern, routef: false, include_callee: include_callee, newline_offsets: newline_offsets)
          i = match_end || (i + 1)
          next
        end

        # route / routeCi / routex IDENT — the path is supplied via a
        # string constant rather than a literal, e.g. `route Urls.index`
        # where `let index = "/"`. Resolve it against file-level `let`
        # bindings; if the name is unknown, skip without emitting (no
        # phantom endpoint).
        route_const_match = ROUTE_CONST_RE.match_at_byte_index(cleaned, byte_i, options: NO_UTF_CHECK)
        if route_const_match && token_boundary?(cleaned, i)
          ident = route_const_match[1]
          match_end = route_const_match.end(0)
          resolved = string_constants[ident.split('.').last]?
          if resolved
            emit_route(path, content, cleaned, i, scope_stack, resolved, routef: false, include_callee: include_callee, newline_offsets: newline_offsets)
          end
          i = match_end || (i + 1)
          next
        end

        i += 1
      end
    end

    # Precomputes the byte offset of every character position in `chars`
    # (index `chars.size` maps to the total byte length). Computed once in
    # O(n) so the scan loop can look up `Regex#match_at_byte_index`'s start
    # position in O(1) instead of re-deriving it (or re-slicing the string)
    # on every iteration.
    private def char_byte_offsets(chars : Array(Char)) : Array(Int32)
      offsets = Array(Int32).new(chars.size + 1)
      acc = 0
      offsets << acc
      chars.each do |c|
        acc += c.bytesize
        offsets << acc
      end
      offsets
    end

    # Collects `let NAME = "VALUE"` string bindings so routes that
    # reference a path constant (`route Urls.index`) can be resolved.
    # Keyed by the bare binding name (last segment of any qualifier);
    # the first definition wins. Only direct string literals are
    # captured — concatenations and computed paths are ignored.
    private def collect_string_constants(text : String) : Hash(String, String)
      consts = {} of String => String
      text.scan(/\blet\s+(?:mutable\s+|rec\s+|inline\s+)*([A-Za-z_][A-Za-z0-9_']*)\s*(?::[^=\n]+)?=\s*"((?:[^"\\]|\\.)*)"/) do |m|
        name = m[1]
        next if consts.has_key?(name)
        consts[name] = m[2]
      end
      consts
    end

    # True when `offset` begins a fresh token, i.e. the preceding char is
    # not part of an identifier. Guards combinator matches so substrings
    # like the `route` inside `myroute "/x"` are not mistaken for routes.
    private def token_boundary?(text : String, offset : Int32) : Bool
      return true if offset == 0
      prev = text[offset - 1]
      !(prev.alphanumeric? || prev == '_' || prev == '\'' || prev == '.')
    end

    private def current_prefix(scope_stack : Array(SubRouteScope)) : String
      scope_stack.map { |s| s[:prefix] }.join("")
    end

    private def current_prefix_params(scope_stack : Array(SubRouteScope)) : Array(Param)
      params = [] of Param
      scope_stack.each { |s| params.concat(s[:params]) }
      params
    end

    # Innermost scope-supplied HTTP verb (Endpoint Routing wrapper), if any.
    private def scope_method(scope_stack : Array(SubRouteScope)) : String?
      scope_stack.reverse_each do |scope|
        m = scope[:method]
        return m if m
      end
      nil
    end

    # Distinguishes a Giraffe Endpoint-Routing `GET [...]` wrapper from
    # an ordinary `GET >=> route ...` chain where `[` appears later on
    # the same line in a literal context. We require the `[` to follow
    # the verb after only whitespace AND for there to be no `>=>`
    # between the verb and the bracket.
    private def verb_list_method_context?(text : String, offset : Int32) : Bool
      # Token-boundary check: must be preceded by start-of-string,
      # whitespace, `[`, `;`, or `,`.
      if offset > 0
        prev = text[offset - 1]
        return false unless prev.whitespace? || prev == '[' || prev == ';' || prev == ',' || prev == '('
      end
      true
    end

    private def emit_route(path : String, content : String, cleaned : String,
                           offset : Int32, scope_stack : Array(SubRouteScope),
                           path_pattern : String, routef : Bool, include_callee : Bool,
                           newline_offsets : Array(Int32), bind : Bool = false)
      url, params = if bind
                      translate_route_bind(path_pattern)
                    elsif routef
                      translate_routef(path_pattern)
                    else
                      {path_pattern, [] of Param}
                    end
      full_url = current_prefix(scope_stack) + url
      full_params = current_prefix_params(scope_stack) + params

      method = find_method_for_route(cleaned, offset) || scope_method(scope_stack)
      methods = method ? [method] : FALLBACK_METHODS

      line = line_for_offset(newline_offsets, offset)
      details = Details.new(PathInfo.new(path, line))
      callees = include_callee ? callees_for_route(path, content, cleaned, offset, newline_offsets) : [] of Noir::FsharpCalleeExtractor::Entry

      methods.each do |verb|
        endpoint_params = full_params.map { |p| Param.new(p.name, p.value, p.param_type) }
        endpoint = Endpoint.new(full_url, verb, endpoint_params, details)
        Noir::FsharpCalleeExtractor.attach_to(endpoint, callees)
        @result << endpoint
      end
    end

    private def callees_for_route(path : String,
                                  content : String,
                                  cleaned : String,
                                  offset : Int32,
                                  newline_offsets : Array(Int32)) : Array(Noir::FsharpCalleeExtractor::Entry)
      body_info = route_handler_body(cleaned, offset)
      return [] of Noir::FsharpCalleeExtractor::Entry unless body_info

      body, body_start = body_info
      start_line = line_for_offset(newline_offsets, body_start)
      Noir::FsharpCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def route_handler_body(text : String, offset : Int32) : Tuple(String, Int32)?
      # Integer `String#[](Int)` is O(n) on non-ASCII source (one multi-byte
      # char defeats the single-byte optimization), so the char walks in the
      # helpers below would be O(n²); materialize once here and thread the
      # array through them instead.
      chars = text.chars
      body_start = route_pattern_end(chars, offset)
      return unless body_start

      route_line_start = line_start_for_offset(text, offset)
      base_indent = indentation_at(chars, route_line_start)
      body_end = route_handler_end(text, body_start, base_indent)
      return if body_end <= body_start

      {text[body_start...body_end], body_start}
    end

    # Walks a materialized `Array(Char)` (built once by `route_handler_body`)
    # so each access is O(1) — integer `String#[]` would be O(n) on non-ASCII
    # source, making this walk O(n²).
    private def route_pattern_end(chars : Array(Char), offset : Int32) : Int32?
      i = offset
      while i < chars.size && identifier_char?(chars[i])
        i += 1
      end

      while i < chars.size && chars[i].whitespace?
        i += 1
      end

      return unless i < chars.size

      if chars[i] == '"'
        string_end = find_string_end(chars, i)
        return unless string_end
        return string_end + 1
      end

      # Path supplied as a constant reference (`route Urls.index`): skip
      # the qualified identifier so the handler body that follows is
      # still available for callee extraction.
      if identifier_char?(chars[i])
        j = i
        while j < chars.size && (identifier_char?(chars[j]) || chars[j] == '.' || chars[j] == '\'')
          j += 1
        end
        return j
      end

      nil
    end

    # Scans the shared `Array(Char)` threaded down from `route_handler_body`
    # (via `route_pattern_end`) — see the O(n²) rationale there.
    private def find_string_end(chars : Array(Char), quote_index : Int32) : Int32?
      i = quote_index + 1
      escaping = false

      while i < chars.size
        char = chars[i]
        if escaping
          escaping = false
        elsif char == '\\'
          escaping = true
        elsif char == '"'
          return i
        end
        i += 1
      end

      nil
    end

    private def route_handler_end(text : String, start : Int32, base_indent : Int32) : Int32
      first_line = true
      line_start = line_start_for_offset(text, start)
      cursor = line_start

      while cursor < text.size
        line_end = text.index('\n', cursor) || text.size
        line = text[cursor...line_end]

        if !first_line && route_handler_stop_line?(line, base_indent)
          return cursor
        end

        first_line = false
        cursor = line_end + 1
      end

      text.size
    end

    private def route_handler_stop_line?(line : String, base_indent : Int32) : Bool
      stripped = line.strip
      return false if stripped.empty?

      indent = indentation_of_line(line)
      return false if indent > base_indent
      return true if stripped.starts_with?("]") || stripped.starts_with?(")")
      return true if stripped.match(/\A(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b\s*$/)

      !!stripped.match(ROUTE_HANDLER_STOP_RE)
    end

    private def line_start_for_offset(text : String, offset : Int32) : Int32
      return 0 if offset <= 0

      line_start_raw = text.rindex('\n', offset - 1)
      line_start_raw ? line_start_raw + 1 : 0
    end

    # Indexes the shared `Array(Char)` threaded down from
    # `route_handler_body` — see the O(n²) rationale there.
    private def indentation_at(chars : Array(Char), line_start : Int32) : Int32
      count = 0
      i = line_start
      while i < chars.size
        char = chars[i]
        if char == ' '
          count += 1
        elsif char == '\t'
          count += 2
        else
          break
        end
        i += 1
      end
      count
    end

    private def indentation_of_line(line : String) : Int32
      count = 0
      line.each_char do |char|
        if char == ' '
          count += 1
        elsif char == '\t'
          count += 2
        else
          break
        end
      end
      count
    end

    private def identifier_char?(char : Char) : Bool
      char.alphanumeric? || char == '_'
    end

    private def translate_routef(pattern : String) : Tuple(String, Array(Param))
      params = [] of Param
      buffer = String::Builder.new
      i = 0
      counter = Hash(String, Int32).new(0)

      while i < pattern.size
        c = pattern[i]
        if c == '%' && i + 1 < pattern.size
          spec = pattern[i + 1]
          type = ROUTEF_PARAM_TYPES[spec]?
          if type
            counter[type] += 1
            name = counter[type] == 1 ? type : "#{type}_#{counter[type]}"
            buffer << ":#{name}"
            params << Param.new(name, type, "path")
            i += 2
            next
          end
        end
        buffer << c
        i += 1
      end

      {buffer.to_s, params}
    end

    # Translates a `routeBind<'T>` pattern, turning `{name}` placeholders
    # into `:name` path params. Property types are unknown at the route
    # site, so each bound segment is reported as a string path param.
    # Non-placeholder text (including trailing regex like `(/?)`) is kept
    # verbatim.
    private def translate_route_bind(pattern : String) : Tuple(String, Array(Param))
      params = [] of Param
      buffer = String::Builder.new
      i = 0

      while i < pattern.size
        c = pattern[i]
        if c == '{'
          close = pattern.index('}', i + 1)
          if close
            name = pattern[(i + 1)...close]
            if !name.empty? && name.each_char.all? { |ch| identifier_char?(ch) }
              buffer << ":#{name}"
              params << Param.new(name, "string", "path")
              i = close + 1
              next
            end
          end
        end
        buffer << c
        i += 1
      end

      {buffer.to_s, params}
    end

    # Walks backwards through `>=>`-connected continuation lines,
    # accumulating preceding text so that an HTTP method filter
    # declared on a previous line still attaches to the route.
    private def find_method_for_route(text : String, route_pos : Int32) : String?
      cursor = route_pos
      collected = String::Builder.new

      loop do
        line_start_raw = cursor > 0 ? text.rindex('\n', cursor - 1) : nil
        line_start = line_start_raw ? line_start_raw + 1 : 0
        line = text[line_start...cursor]
        collected << line
        collected << ' '

        break if line_start == 0

        prev_le = line_start - 1 # position of the '\n' that ended the previous line
        prev_ls_raw = prev_le > 0 ? text.rindex('\n', prev_le - 1) : nil
        prev_ls = prev_ls_raw ? prev_ls_raw + 1 : 0
        prev_line = text[prev_ls...prev_le]
        # Continue across the line break only when the chain is
        # explicitly extended via `>=>` (either trailing or leading).
        if prev_line.rstrip.ends_with?(">=>") || line.lstrip.starts_with?(">=>")
          cursor = prev_le
        else
          break
        end
      end

      window = collected.to_s
      methods = METHOD_WORD_PATTERNS.select { |_, pattern| window.match(pattern) }.map { |m, _| m }
      methods.first?
    end

    # Returns the index just past the string literal that opens at `open_idx`
    # (which must be a `"`). Handles triple-quoted (`"""…"""`) and ordinary
    # backslash-escaped strings; an unterminated literal returns the end of text.
    # Scans over an `Array(Char)` so each access is O(1) — integer `String#[]`
    # would be O(n) on non-ASCII source, making the skip itself O(n²).
    private def skip_string_literal(chars : Array(Char), open_idx : Int32) : Int32
      size = chars.size
      if open_idx + 2 < size && chars[open_idx + 1] == '"' && chars[open_idx + 2] == '"'
        j = open_idx + 3
        while j + 2 < size
          break if chars[j] == '"' && chars[j + 1] == '"' && chars[j + 2] == '"'
          j += 1
        end
        return j + 2 < size ? j + 3 : size
      end

      j = open_idx + 1
      while j < size
        c = chars[j]
        if c == '\\'
          j += 2
          next
        elsif c == '"'
          return j + 1
        end
        j += 1
      end
      size
    end

    private def find_matching_paren(text : String, open_idx : Int32) : Int32?
      find_matching_delimiter(text, open_idx, '(', ')')
    end

    private def find_matching_bracket(text : String, open_idx : Int32) : Int32?
      find_matching_delimiter(text, open_idx, '[', ']')
    end

    # Returns the index of the closing quote if chars[i] opens a genuine F#
    # char literal ('c', '\n', '\\', 'A', '\x41', ...); nil if the apostrophe is
    # a generic type param (`<'T>`) or a tick identifier (`route'`), which must
    # NOT be treated as a string delimiter.
    private def fsharp_char_literal_close(chars : Array(Char), i : Int32) : Int32?
      if i > 0
        prev = chars[i - 1]
        return if prev.alphanumeric? || prev == '_' || prev == '\'' || prev == '<'
      end
      return if i + 1 >= chars.size

      if chars[i + 1] == '\\'
        j = i + 2
        limit = i + 10
        while j < chars.size && j <= limit
          return j if chars[j] == '\''
          j += 1
        end
        nil
      else
        (i + 2 < chars.size && chars[i + 2] == '\'') ? i + 2 : nil
      end
    end

    private def find_matching_delimiter(text : String, open_idx : Int32,
                                        opener : Char, closer : Char) : Int32?
      chars = text.chars
      return unless open_idx < chars.size && chars[open_idx] == opener
      depth = 1
      i = open_idx + 1
      in_string = false

      while i < chars.size && depth > 0
        c = chars[i]
        if in_string
          if c == '\\' && i + 1 < chars.size
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
          next
        end

        # An apostrophe is usually a generic param (<'T>) or a tick identifier
        # (route'), not a string. Only skip it when it opens a real char literal.
        if c == '\''
          i = (close = fsharp_char_literal_close(chars, i)) ? close + 1 : i + 1
          next
        end

        case c
        when '"'
          in_string = true
        when opener
          depth += 1
        when closer
          depth -= 1
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    private def strip_fsharp_comments(text : String) : String
      result = String::Builder.new
      i = 0
      chars = text.chars
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == string_quote
            in_string = false
          end
          result << c
          i += 1
          next
        end

        if c == '"'
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        # Apostrophe: a generic param (<'T>) or tick identifier (route') is NOT
        # a string — passing it through verbatim keeps later comments strippable.
        # Only a genuine char literal is copied as an opaque unit.
        if c == '\''
          if close = fsharp_char_literal_close(chars, i)
            (i..close).each { |k| result << chars[k] }
            i = close + 1
          else
            result << c
            i += 1
          end
          next
        end

        # Line comments: //
        if i + 1 < chars.size && c == '/' && chars[i + 1] == '/'
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          if i < chars.size
            result << chars[i]
            i += 1
          end
          next
        end

        # Block comments: (* ... *) — F# uses these instead of /* */.
        if i + 1 < chars.size && c == '(' && chars[i + 1] == '*'
          depth = 1
          result << ' '
          result << ' '
          i += 2
          while i + 1 < chars.size && depth > 0
            if chars[i] == '(' && chars[i + 1] == '*'
              depth += 1
              result << ' '
              result << ' '
              i += 2
            elsif chars[i] == '*' && chars[i + 1] == ')'
              depth -= 1
              result << ' '
              result << ' '
              i += 2
            else
              result << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    # Char index of every newline in the analyzed file, in ascending order.
    # Computed once per file (O(n), non-ASCII-safe via `each_char_with_index`)
    # so `line_for_offset` can binary-search it instead of re-walking from
    # the start of the file on every call — see that method's doc comment.
    private def collect_newline_offsets(text : String) : Array(Int32)
      offsets = [] of Int32
      text.each_char_with_index do |c, idx|
        offsets << idx if c == '\n'
      end
      offsets
    end

    # `emit_route` calls this once per matched route (and again per callee
    # extraction), in file order but always against the *same* file. Walking
    # from the start of the file for every call — the previous
    # `Char::Reader.new(content)` implementation — is O(file length) per
    # call, so scanning N routes costs O(N * file length): a file with 4x
    # the routes (and proportionally more content) measured ~16x the scan
    # time. Binary-searching a precomputed, sorted newline-offset table
    # turns each lookup into O(log n).
    private def line_for_offset(newline_offsets : Array(Int32), offset : Int32) : Int32
      return 1 if offset <= 0
      idx = newline_offsets.bsearch_index { |pos| pos >= offset }
      count = idx || newline_offsets.size
      count + 1
    end
  end
end
