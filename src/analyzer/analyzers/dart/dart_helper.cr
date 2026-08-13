require "../../../utils/path_scope"
require "../../../miniparsers/dart_callee_extractor"

module Analyzer::Dart
  # Shared helpers for the Dart framework analyzers (Dart Frog, Shelf,
  # Serverpod). Kept framework-agnostic so each analyzer can opt in
  # without duplicating path/string conventions.
  module Helper
    extend self

    # Standard Dart test-file conventions. The Dart tooling discovers
    # tests under a project-root `test/` directory and via the
    # `*_test.dart` suffix; neither ever serves real traffic. Dart Frog
    # in particular mirrors the route tree under `test/routes/`, so a
    # naive `/routes/` match would surface every mock handler as a live
    # endpoint. Centralized so every Dart analyzer can opt in via
    # `next if Helper.test_path?(path, base_paths)`.
    #
    #   * `/test/`, `test/` — Dart's `dart test` discovery root and the
    #                         Dart Frog `test/routes/` mirror tree
    #   * `*_test.dart`     — the canonical Dart unit-test suffix
    def test_path?(path : String, base_path : String? = nil) : Bool
      relative = relative_for_match(path, base_path)
      return true if relative.includes?("/test/")
      return true if relative.starts_with?("test/")
      File.basename(path).ends_with?("_test.dart")
    end

    def test_path?(path : String, base_paths : Array(String)) : Bool
      test_path?(path, base_path_for(path, base_paths))
    end

    # Replace `//` line and `/* */` block comments with spaces, leaving
    # string literals and overall byte offsets intact so downstream
    # regex/offset logic still lines up with the original source.
    def strip_comments(text : String) : String
      result = String::Builder.new
      chars = text.chars
      i = 0
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
          end
          in_string = false if c == string_quote
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        if c == '/' && i + 1 < chars.size && chars[i + 1] == '/'
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          next
        end

        if c == '/' && i + 1 < chars.size && chars[i + 1] == '*'
          result << "  "
          i += 2
          while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
            result << (chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
          if i + 1 < chars.size
            result << "  "
            i += 2
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    # Pull the contents of a leading single/double-quoted string literal
    # from an argument expression, honouring backslash escapes. Returns
    # nil when the expression doesn't start with a string literal.
    def extract_string_literal(text : String) : String?
      stripped = text.strip
      return if stripped.empty?
      quote = stripped[0]
      return unless quote == '"' || quote == '\''
      i = 1
      while i < stripped.size
        c = stripped[i]
        if c == '\\' && i + 1 < stripped.size
          i += 2
          next
        end
        return stripped[1...i] if c == quote
        i += 1
      end
      nil
    end

    # Index of the `)` closing the `(` at `open_idx`, or nil when the
    # expression never balances. String literals are skipped so a paren
    # inside `'a)b'` doesn't close the call, and backslash escapes inside
    # them are honoured.
    #
    # Both the argument and the result stay in CHAR space, consistent with
    # `Regex::MatchData#begin`, `Analyzer#line_number_for_index` and the
    # `char_index_to_byte_index` conversions the analyzers use for callee
    # extraction.
    def find_matching_paren(text : String, open_idx : Int32) : Int32?
      # `String#[]` re-walks from byte 0 on every call once the source
      # contains any multi-byte char, turning this scan O(n^2); index a
      # materialized Array(Char) instead (O(1) per access).
      chars = text.chars
      depth = 0
      i = open_idx
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]
        if in_string
          if c == '\\' && i + 1 < chars.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    # Char index of the first comma at paren/brace/bracket depth zero
    # between `start` and `limit`, or nil when the call has a single
    # argument.
    def first_top_level_comma(text : String, start : Int32, limit : Int32) : Int32?
      chars = text.chars
      depth = 0
      i = start
      in_string = false
      string_quote = '\0'

      while i < limit
        c = chars[i]
        if in_string
          if c == '\\' && i + 1 < chars.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '(', '{', '['
          depth += 1
        when ')', '}', ']'
          depth -= 1 if depth > 0
        when ','
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    # Split a call's argument list on top-level commas. Each bracket kind
    # (`()`, `{}`, `[]`, `<>`) gets its own counter so a generic argument
    # (`Map<String, int>`) and a collection literal (`[a, b]`) both keep
    # their inner commas, and string literals are skipped so a comma inside
    # `'a,b'` never splits. The trailing segment is always emitted, so a
    # single-argument call yields a one-element array.
    #
    # Note: `Serverpod#split_top_level_commas` is deliberately NOT this
    # method — it tracks only `<`/`(` on one shared counter and is not
    # string-aware, matching the narrower shapes it parses.
    def split_top_level_args(text : String) : Array(String)
      result = [] of String
      chars = text.chars
      depth_paren = 0
      depth_brace = 0
      depth_bracket = 0
      depth_angle = 0
      start = 0
      i = 0
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]
        if in_string
          if c == '\\' && i + 1 < chars.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth_paren += 1
        when ')'
          depth_paren -= 1 if depth_paren > 0
        when '{'
          depth_brace += 1
        when '}'
          depth_brace -= 1 if depth_brace > 0
        when '['
          depth_bracket += 1
        when ']'
          depth_bracket -= 1 if depth_bracket > 0
        when '<'
          depth_angle += 1
        when '>'
          depth_angle -= 1 if depth_angle > 0
        when ','
          if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0 && depth_angle == 0
            result << chars[start...i].join
            start = i + 1
          end
        else
          # ignore
        end
        i += 1
      end
      result << chars[start..].join if start <= chars.size
      result
    end

    # Matches a bare handler reference (`_createUser`, `auth.handler`)
    # passed as a route's handler argument.
    HANDLER_REFERENCE_REGEX = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/

    # Callees for a route's handler argument, where `handler_start` is the
    # CHAR index at which the handler expression begins (typically the
    # char just past the first top-level comma).
    #
    # A plain function reference (`_createUser`, `auth.handler`) can't be
    # resolved cross-file yet, so the reference itself is recorded as the
    # callee.
    #
    # `extract_body_after` scans by BYTE offset, hence the char-to-byte
    # conversion. It skips past the leading `(req, res)` lambda params to
    # the `=>`/`{` body, so a trailing `middleware:` argument after the
    # body is naturally excluded.
    #
    # Shelf keeps its own variant: it derives the handler start from the
    # call's closing paren instead of a comma index, so the two are not
    # interchangeable.
    def handler_callees(handler_arg : String,
                        content : String,
                        handler_start : Int32,
                        path : String,
                        line : Int32) : Array(Noir::DartCalleeExtractor::Entry)
      stripped = handler_arg.strip

      unless stripped.starts_with?('(')
        return [] of Noir::DartCalleeExtractor::Entry unless stripped.matches?(HANDLER_REFERENCE_REGEX)
        return [{stripped, path, line}] of Noir::DartCalleeExtractor::Entry
      end

      start_b = content.char_index_to_byte_index(handler_start)
      return [] of Noir::DartCalleeExtractor::Entry unless start_b
      body_info = Noir::DartCalleeExtractor.extract_body_after(content, start_b)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    # Build an endpoint from an already-normalized URL, promoting every
    # `{name}` capture in it to a path param and attaching the callees.
    # Analyzers whose endpoints carry extra state (Dart Frog's websocket
    # flag, `dart:io` HttpServer's inherited params) keep their own.
    def build_endpoint(url : String,
                       verb : String,
                       path : String,
                       line : Int32,
                       callees : Array(Noir::DartCalleeExtractor::Entry)) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, line))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      endpoint
    end

    private def relative_for_match(path : String, base_path : String?) : String
      Noir::PathScope.relative_under(path, base_path)
    end

    private def base_path_for(path : String, base_paths : Array(String)) : String?
      Noir::PathScope.longest_base(path, base_paths)
    end
  end
end
