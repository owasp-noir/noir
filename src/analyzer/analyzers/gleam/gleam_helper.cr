module Analyzer::Gleam
  # Shared helpers for the Gleam framework analyzers (Wisp, Mist).
  module Helper
    extend self

    # Blank out `//` line comments (this covers `///` and `////` doc
    # comments too) while PRESERVING newlines/offsets, so a comment never
    # collapses lines and shifts every later endpoint's reported line
    # number. Gleam has no block comments.
    #
    # `"..."` strings are skipped so a URL literal like
    # `"https://example.com"` doesn't truncate the line. Gleam strings may
    # span multiple lines, so the scanner tracks them across newlines.
    def strip_gleam_comments(text : String) : String
      return text unless text.includes?('/')

      result = String::Builder.new(text.bytesize)
      chars = text.chars
      i = 0
      size = chars.size

      while i < size
        c = chars[i]

        if c == '"'
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
            break if ch == '"'
          end
          next
        end

        if c == '/' && i + 1 < size && chars[i + 1] == '/'
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

    # Renders a Gleam list pattern from a `case wisp.path_segments(req)`
    # arm into a noir URL plus its path params.
    #
    # Segment forms:
    #   * `"users"`      — a string literal segment.
    #   * `id`           — a bound variable, i.e. a path parameter.
    #   * `_` / `_name`  — a discarded segment; still a parameter position,
    #                      but unnamed, so it renders as a generic binding.
    #   * `..` / `..rest`— matches all remaining segments (wildcard).
    def parse_segments(segments : Array(String)) : Tuple(String, Array(Param))
      params = [] of Param
      seen = Set(String).new
      rendered = [] of String
      discard_index = 0

      segments.each do |raw|
        segment = raw.strip
        next if segment.empty?

        if segment.starts_with?("..")
          rendered << "*"
          next
        end

        if segment.starts_with?('"')
          literal = segment.strip('"')
          rendered << literal unless literal.empty?
          next
        end

        if segment.starts_with?('_')
          # `_` and `_ignored` are discards: a path position that varies
          # but is never read. Name them positionally so two discards in
          # one path don't collide.
          discard_index += 1
          name = discard_index == 1 ? "param" : "param#{discard_index}"
          rendered << ":#{name}"
          params << Param.new(name, "", "path") if seen.add?(name)
          next
        end

        if segment.matches?(/\A[a-z][A-Za-z0-9_]*\z/)
          rendered << ":#{segment}"
          params << Param.new(segment, "", "path") if seen.add?(segment)
          next
        end

        # Anything else (a constructor pattern, a nested list, an `as`
        # binding) isn't a shape we can render faithfully.
        rendered << segment
      end

      url = rendered.empty? ? "/" : "/#{rendered.join("/")}"
      {url, params}
    end

    # Returns the balanced `{…}` span beginning at `open_idx`, braces
    # included, or nil if it never closes. String contents are skipped so
    # a brace inside a literal doesn't unbalance the count — Gleam
    # strings may span newlines and routinely embed JS/HTML.
    def balanced_span(text : String, open_idx : Int32) : String?
      chars = text.chars
      return unless chars[open_idx]? == '{'

      depth = 0
      i = open_idx
      while i < chars.size
        c = chars[i]

        if c == '"'
          i += 1
          while i < chars.size
            ch = chars[i]
            if ch == '\\'
              i += 2
              next
            end
            i += 1
            break if ch == '"'
          end
          next
        end

        if c == '{'
          depth += 1
        elsif c == '}'
          depth -= 1
          return text[open_idx..i] if depth == 0
        end

        i += 1
      end

      nil
    end

    # Splits a case pattern on its top-level `|` alternates, so
    # `["a"] | ["b", _]` becomes two independent path patterns.
    def split_alternatives(pattern : String) : Array(String)
      alternatives = [] of String
      current = String::Builder.new
      depth = 0
      in_string = false
      chars = pattern.chars
      i = 0

      while i < chars.size
        c = chars[i]

        if in_string
          current << c
          if c == '\\' && i + 1 < chars.size
            current << chars[i + 1]
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
          next
        end

        case c
        when '"'
          in_string = true
          current << c
        when '[', '(', '{'
          depth += 1
          current << c
        when ']', ')', '}'
          depth -= 1
          current << c
        when '|'
          if depth == 0
            alternatives << current.to_s
            current = String::Builder.new
          else
            current << c
          end
        else
          current << c
        end

        i += 1
      end

      tail = current.to_s
      alternatives << tail unless tail.strip.empty?
      result = alternatives.map(&.strip).reject(&.empty?)
      result.empty? ? [pattern.strip] : result
    end

    # Splits a case-arm list pattern body (the text between `[` and `]`)
    # into its top-level comma-separated segments, ignoring commas nested
    # inside strings, brackets, parens or braces.
    def split_pattern_segments(body : String) : Array(String)
      segments = [] of String
      current = String::Builder.new
      depth = 0
      in_string = false
      i = 0
      chars = body.chars

      while i < chars.size
        c = chars[i]

        if in_string
          current << c
          if c == '\\' && i + 1 < chars.size
            current << chars[i + 1]
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
          next
        end

        case c
        when '"'
          in_string = true
          current << c
        when '[', '(', '{'
          depth += 1
          current << c
        when ']', ')', '}'
          depth -= 1
          current << c
        when ','
          if depth == 0
            segments << current.to_s
            current = String::Builder.new
          else
            current << c
          end
        else
          current << c
        end

        i += 1
      end

      tail = current.to_s
      segments << tail unless tail.strip.empty?
      segments.map(&.strip).reject(&.empty?)
    end
  end
end
