module Analyzer::Erlang
  # Shared helpers for the Erlang framework analyzers (Cowboy, Elli).
  module Helper
    extend self

    # rebar3 keeps Common Test suites (`*_SUITE.erl`) and EUnit modules
    # (`*_tests.erl`) under `test/`; they build throwaway dispatch tables
    # for `rebar3 ct`/`eunit`, never served. Takes the scan-base-relative
    # path so a checkout under a `test/` ancestor is not wiped; the suffix
    # rules still catch a scan whose base is the test directory itself.
    def test_path?(relative_path : String) : Bool
      return true if relative_path.includes?("/test/")
      base = File.basename(relative_path)
      base.ends_with?("_SUITE.erl") || base.ends_with?("_tests.erl")
    end

    # A preprocessor directive that opens a form: at the start of a line or
    # right after the `.` ending the previous form, so several directives on
    # one line (`-ifdef(TEST). -include_lib("x"). -endif.`) are all seen.
    # `else`/`endif` leave their `.` unconsumed, because it is the opening
    # `.` of the next directive on the line.
    DIRECTIVE = /(?:\A|\.)\s*-\s*(?:(ifdef\s*\(\s*TEST\s*\))|(ifndef\s*\(\s*TEST\s*\))|(if(?:n?def)?\s*\()|(else)(?=\s*\.)|(endif)(?=\s*\.))/

    # Blank the lines of every region compiled only when TEST is defined
    # (`-ifdef(TEST). … -endif.`, or the `-else.` branch of
    # `-ifndef(TEST).`), keeping newlines so later line numbers hold. Every
    # open `-if*` is tracked so an `-else.`/`-endif.` pairs with its own
    # conditional; the `-else.` of `-ifdef(TEST).` is the branch compiled
    # without TEST, i.e. production code.
    def mask_ifdef_test(text : String) : String
      return text unless text.includes?("TEST")

      # {is a TEST conditional, current branch is TEST-only}
      frames = [] of Tuple(Bool, Bool)
      result = String::Builder.new(text.bytesize)
      text.each_line(chomp: false) do |line|
        masked = frames.any?(&.[1])
        line.scan(DIRECTIVE) do |m|
          if m[1]?
            frames << {true, true}
          elsif m[2]?
            frames << {true, false}
          elsif m[3]?
            frames << {false, false}
          elsif m[4]?
            if (top = frames.last?) && top[0]
              frames[-1] = {true, !top[1]}
            end
          else
            frames.pop?
          end
          masked ||= frames.any?(&.[1])
        end
        if masked
          result << '\n' if line.ends_with?('\n')
        else
          result << line
        end
      end
      result.to_s
    end

    # Blank out `%` line comments while PRESERVING newlines/offsets, so a
    # comment never collapses lines and shifts every later endpoint's
    # reported line number.
    #
    # Erlang has three constructs a naive `%`-to-end-of-line scan gets
    # wrong, and all three appear in real dispatch tables:
    #   * `"..."` strings — `"100%"` is not a comment.
    #   * `'...'` quoted atoms — `'GET%'`, and more commonly `'_'`.
    #   * `$c` character literals — `$%` IS the percent character, and
    #     `$'`/`$"` are quote characters that must not open a string.
    def strip_erlang_comments(text : String) : String
      return text unless text.includes?('%')

      result = String::Builder.new(text.bytesize)
      chars = text.chars
      i = 0
      size = chars.size

      while i < size
        c = chars[i]

        # `$c` character literal. Consumes the following char verbatim so
        # `$%` / `$"` / `$'` cannot be mistaken for a comment or quote.
        # `$\n` (escape sequence) takes one more char after the backslash.
        if c == '$' && i + 1 < size
          result << c
          nxt = chars[i + 1]
          result << nxt
          i += 2
          if nxt == '\\' && i < size
            result << chars[i]
            i += 1
          end
          next
        end

        if c == '"' || c == '\''
          quote = c
          result << c
          i += 1
          while i < size
            ch = chars[i]
            if ch == '\\' && i + 1 < size
              result << ch
              result << chars[i + 1]
              i += 2
              next
            end
            result << ch
            i += 1
            break if ch == quote
            # An unterminated quote must not swallow the rest of the file.
            break if ch == '\n' && quote == '\''
          end
          next
        end

        if c == '%'
          while i < size && chars[i] != '\n'
            i += 1
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    # Erlang path matches appear both as plain strings (`"/users/:id"`)
    # and as binaries (`<<"/users/:id">>`). Both carry the same syntax.
    #
    # Segment forms, per cowboy_router:
    #   * `:name`      — a binding, i.e. a path parameter.
    #   * `[...]`      — matches all remaining segments (wildcard).
    #   * `[/optional]`— an optional segment.
    #   * `:name[...]` — a binding that also swallows the remainder.
    #
    # Returns the noir-normalized URL plus the bindings as path params.
    def parse_cowboy_path(path_match : String) : Tuple(String, Array(Param))
      params = [] of Param
      seen = Set(String).new
      rendered = [] of String

      path_match.split('/').each do |raw|
        segment = raw.strip
        next if segment.empty?

        # An optional segment `[foo]` still identifies a reachable path,
        # so emit it without the brackets rather than dropping the route.
        # Optionals nest — `"/hats/[page/[:number]]"` splits into `[page`
        # and `[:number]]` — so every delimiter has to come off, not just
        # one on each side.
        stripped = segment.lstrip('[').rstrip(']')
        next if stripped.empty?

        # `[...]` matches every remaining segment. After bracket
        # stripping both it and the `[/...]` spelling read as `...`.
        if stripped == "..."
          rendered << "*"
          next
        end

        # `:name[...]` — a binding that also consumes the remainder.
        trailing_wildcard = false
        if idx = stripped.index('[')
          trailing_wildcard = stripped[idx..].includes?("...")
          stripped = stripped[0...idx]
        end
        next if stripped.empty?

        if stripped.starts_with?(':')
          name = stripped[1..]
          unless name.empty?
            rendered << ":#{name}"
            params << Param.new(name, "", "path") if seen.add?(name)
          end
        else
          rendered << stripped
        end

        rendered << "*" if trailing_wildcard
      end

      url = rendered.empty? ? "/" : "/#{rendered.join("/")}"
      {url, params}
    end
  end
end
