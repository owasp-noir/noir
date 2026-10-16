require "../../../utils/path_scope"
require "../../../utils/top_level_split"
require "../../../utils/c_comments"
require "../../../utils/char_offsets"
require "../../../miniparsers/dart_callee_extractor"

module Analyzer::Dart
  # Shared helpers for the Dart framework analyzers (Dart Frog, Shelf,
  # Serverpod). Kept framework-agnostic so each analyzer can opt in
  # without duplicating path/string conventions.
  module Helper
    extend self

    # Whole path segments, matched on the scan-base-relative path, so
    # `test_app/` or a checkout that itself lives under `tests/` never
    # trips them.
    TEST_DIR_RE      = /(?:\A|\/)(?:tests?|testing|test_utils|test_driver|integration_test)\//
    TEMPLATE_PATH_RE = /__brick__|\{\{/

    # Standard Dart test-file conventions. The Dart tooling discovers
    # tests under a project-root `test/` directory and via the
    # `*_test.dart` suffix; neither ever serves real traffic. Dart Frog
    # in particular mirrors the route tree under `test/routes/`, so a
    # naive `/routes/` match would surface every mock handler as a live
    # endpoint. Centralized so every Dart analyzer can opt in via
    # `next if Helper.test_path?(path, base_paths)`.
    #
    #   * `test/`           — Dart's `dart test` discovery root and the
    #                         Dart Frog `test/routes/` mirror tree
    #   * `tests/`, `testing/`, `test_utils/`, `test_driver/`,
    #     `integration_test/` — test servers and Flutter's test roots
    #                         (Serverpod's `tests/serverpod_test_server`,
    #                         pub_worker's `lib/src/testing/server.dart`)
    #   * `*_test.dart`     — the canonical Dart unit-test suffix
    #   * `__brick__`, `{{` — Mason / Serverpod scaffold templates, which
    #                         only become routes once rendered
    def test_path?(path : String, base_path : String? = nil) : Bool
      relative = relative_for_match(path, base_path)
      return true if relative.matches?(TEST_DIR_RE) || relative.matches?(TEMPLATE_PATH_RE)
      File.basename(path).ends_with?("_test.dart")
    end

    def test_path?(path : String, base_paths : Array(String)) : Bool
      test_path?(path, base_path_for(path, base_paths))
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
    # extraction. Pass `offsets` (built over `text`) when calling once per
    # route: without it the char-to-byte seek is O(open_idx) per call on
    # any source holding a multi-byte char.
    def find_matching_paren(text : String, open_idx : Int32, offsets : Noir::CharOffsets? = nil) : Int32?
      depth = 0
      each_code_char(text, open_idx, text.size, offsets) do |c, i|
        case c
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        end
      end
      nil
    end

    # Char index of the first comma at paren/brace/bracket depth zero
    # between `start` and `limit`, or nil when the call has a single
    # argument.
    def first_top_level_comma(text : String, start : Int32, limit : Int32) : Int32?
      depth = 0
      each_code_char(text, start, limit) do |c, i|
        case c
        when '(', '{', '['
          depth += 1
        when ')', '}', ']'
          depth -= 1 if depth > 0
        when ','
          return i if depth == 0
        end
      end
      nil
    end

    # `Analyzer#line_number_for_index` for many lookups into one file: the
    # newline offsets are collected once, then each lookup is a binary
    # search instead of a rescan from the start of the file per route.
    class LineIndex
      def initialize(content : String)
        @newlines = [] of Int32
        content.each_char_with_index { |char, index| @newlines << index if char == '\n' }
      end

      # 1-based line of a CHAR offset.
      def line_for(char_index : Int32) : Int32
        return 1 if char_index <= 0
        (@newlines.bsearch_index { |newline| newline >= char_index } || @newlines.size) + 1
      end
    end

    # Yields each char outside string literals, with its CHAR index, from
    # `start` up to `limit`. Reads from a byte offset: materialising
    # `text.chars` cost O(file) per call, so a many-route file was O(n^2).
    private def each_code_char(text : String, start : Int32, limit : Int32, offsets : Noir::CharOffsets? = nil, &)
      byte = offsets ? offsets.byte(start) : text.char_index_to_byte_index(start)
      return unless byte
      reader = Char::Reader.new(text, byte)
      i = start
      quote = '\0'

      while i < limit && reader.has_next?
        c = reader.current_char
        if quote != '\0'
          if c == '\\' && reader.pos + reader.current_char_width < text.bytesize
            reader.next_char
            i += 1
          elsif c == quote
            quote = '\0'
          end
        elsif c == '"' || c == '\''
          quote = c
        else
          yield c, i
        end
        reader.next_char
        i += 1
      end
    end

    # Each bracket kind (`()`, `{}`, `[]`, `<>`) gets its own counter so a
    # generic argument (`Map<String, int>`) and a collection literal
    # (`[a, b]`) both keep their inner commas, and string literals are
    # skipped so a comma inside `'a,b'` never splits. Nothing is stripped
    # and every part is kept, the trailing one included, so a
    # single-argument call yields a one-element array.
    #
    # File-local rather than a `Rules` preset: it is the only splitter in
    # the tree that counts `<>` and also keeps every part unstripped, so a
    # central name would have exactly one user.
    SPLIT_ARGS_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace | Noir::TopLevelSplit::Nest::Angle,
      quotes: "\"'",
      escape: Noir::TopLevelSplit::Escape::InQuotes,
      strip: false,
      empties: Noir::TopLevelSplit::Empties::Keep,
      per_kind: true,
      clamp: true,
    )

    # Split a call's argument list on top-level commas.
    #
    # Note: `Serverpod#split_top_level_commas` is deliberately NOT this
    # method — it tracks only `<`/`(` on one shared counter and is not
    # string-aware, matching the narrower shapes it parses. It goes through
    # the same shared splitter with its own `Rules`, so the difference is
    # now two constants to compare rather than two loops to diff.
    def split_top_level_args(text : String) : Array(String)
      Noir::TopLevelSplit.split(text, ',', SPLIT_ARGS_RULES)
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

    # Request-input reads. `uri` is dart:io's and Dart Frog's request URI,
    # `url`/`requestedUri` are Shelf's.
    QUERY_PARAM_REGEX  = /\.(?:uri|url|requestedUri)\s*\.\s*queryParameters(?:All)?\s*\[\s*r?["']([^"']+?)["']\s*\]/
    HEADER_VALUE_REGEX = /\.headers\s*\.\s*value\s*\(\s*r?["']([^"']+?)["']/
    HEADER_INDEX_REGEX = /\.headers\s*\[\s*r?["']([^"']+?)["']\s*\]/
    # `final q = request.url.queryParameters;` / `final body = await
    # request.json();` / `jsonDecode(await request.readAsString())` — the
    # variable is then read as `q['x']`.
    QUERY_ALIAS_REGEX = /\b([A-Za-z_]\w*)\s*=\s*[\w.]*\.(?:uri|url|requestedUri)\s*\.\s*queryParameters(?:All)?\s*;/
    JSON_BODY_REGEX   = /\.(?:json|readAsString)\s*\(\s*\)/
    JSON_ALIAS_REGEX  = /\b([A-Za-z_]\w*)\s*=\s*(?:await\s+)?(?:jsonDecode\s*\(\s*(?:await\s+)?)?[\w.]*\.(?:json|readAsString)\s*\(\s*\)/
    FORM_BODY_REGEX   = /\.formData\s*\(\s*\)/
    INDEX_READ_REGEX  = /(?<![\w$.])([A-Za-z_]\w*)\s*\[\s*r?["']([^"']+?)["']\s*\]/

    # Query, header and body inputs a handler body reads. `body` should be
    # comment-stripped. A body read whose keys can't be seen becomes one
    # `body` param, as in the dart:io analyzer.
    def request_params(body : String) : Array(Param)
      params = [] of Param
      add = ->(name : String, type : String) do
        params << Param.new(name, "", type) unless params.any? { |p| p.name == name && p.param_type == type }
      end
      body.scan(QUERY_PARAM_REGEX) { |m| add.call(m[1], "query") }
      body.scan(HEADER_VALUE_REGEX) { |m| add.call(m[1], "header") }
      body.scan(HEADER_INDEX_REGEX) { |m| add.call(m[1], "header") }

      query_aliases = body.scan(QUERY_ALIAS_REGEX).map(&.[1])
      json_aliases = body.scan(JSON_ALIAS_REGEX).map(&.[1])
      json_keys = false
      unless query_aliases.empty? && json_aliases.empty?
        body.scan(INDEX_READ_REGEX) do |m|
          if query_aliases.includes?(m[1])
            add.call(m[2], "query")
          elsif json_aliases.includes?(m[1])
            add.call(m[2], "json")
            json_keys = true
          end
        end
      end
      add.call("body", "json") if !json_keys && body.matches?(JSON_BODY_REGEX)
      add.call("body", "form") if body.matches?(FORM_BODY_REGEX)
      params
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
