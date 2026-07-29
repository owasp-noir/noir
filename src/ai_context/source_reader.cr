require "../models/code_locator"
require "../utils/text_file"

module NoirAIContext
  # Reads source files once (cached per path) and extracts the
  # contextual snippets the augmentor attaches to AIContext entries:
  # a fixed-radius window around a line, or a heuristic "route scope"
  # that walks a handler block to its end across brace / Python-indent
  # / Ruby-`end` styles.
  class SourceReader
    MAX_SNIPPET_CHARS     = 240
    MAX_ROUTE_SCOPE_LINES =  12

    # Maximum number of decorator / annotation lines to capture
    # *before* path_info.line. Lets negative-protection markers
    # (`@csrf_exempt`, `@PreAuthorize`, `@CrossOrigin`) reach the
    # source-scan even when the analyzer sets path_line to the
    # function `def` rather than the decorator above it.
    MAX_LEAD_DECORATOR_LINES = 4

    @file_cache : Hash(String, Array(String))
    @snippet_cache : Hash(String, String)
    @route_scope_cache : Hash(String, String)

    def initialize
      @file_cache = {} of String => Array(String)
      @snippet_cache = {} of String => String
      @route_scope_cache = {} of String => String
    end

    def snippet_for(path : String?, line : Int32?, radius : Int32) : String?
      return unless path && line
      return if line < 1

      cache_key = "#{path}:#{line}:#{radius}"
      if cached = @snippet_cache[cache_key]?
        return cached
      end

      lines = read_lines(path)
      return if line > lines.size

      start_idx = Math.max(line - radius - 1, 0)
      end_idx = Math.min(line + radius - 1, lines.size - 1)
      selected = [] of String

      # Blank lines carry no evidence, and every entry is already
      # prefixed with its own line number, so dropping them loses
      # nothing an LLM or a reviewer can use. Emitting them produced
      # bare `N: ` placeholders — the run of blank lines that precedes
      # most handlers turned into `5: | 6: | 7: | …` at the front of
      # the snippet — and spent part of the character budget that the
      # surrounding code needs.
      (start_idx..end_idx).each do |idx|
        stripped = lines[idx].strip
        next if stripped.empty?

        selected << "#{idx + 1}: #{stripped}"
      end

      snippet = selected.join(" | ").gsub(/\s+/, " ").strip
      return if snippet.empty?
      snippet = snippet.size > MAX_SNIPPET_CHARS ? snippet[0, MAX_SNIPPET_CHARS] : snippet
      @snippet_cache[cache_key] = snippet
      snippet
    end

    # `max_lines` / `max_chars` default to the limits every caller used
    # before they were parameterized. A caller that needs to see further
    # into the handler — `sensitive_response` has to find a response
    # emitter and a credential key in the *same* scope, and they are
    # routinely more than 12 lines apart — raises them. The block-boundary
    # walk below is unchanged either way, so a wider window still stops at
    # the end of this handler rather than bleeding into the next one.
    def route_scope_snippet_for(path : String?,
                                line : Int32?,
                                max_lines : Int32 = MAX_ROUTE_SCOPE_LINES,
                                max_chars : Int32 = MAX_SNIPPET_CHARS) : String?
      return unless path && line
      return if line < 1

      cache_key = "#{path}:#{line}:#{max_lines}:#{max_chars}"
      if cached = @route_scope_cache[cache_key]?
        return cached
      end

      lines = read_lines(path)
      return if line > lines.size

      # Look back from path_line-1 for consecutive decorator /
      # annotation lines and blank lines between them. Stops at the
      # first line that's not a decorator / annotation / blank —
      # that's the end of the preceding declaration boundary.
      #
      # A blank line only lets the scan *continue* (decorators are
      # often separated by one); it is not itself evidence, so it is
      # never appended. Appending them emitted bare `N: ` placeholders
      # for the run of blank lines that precedes almost every handler,
      # which read as a bug and — worse — spent part of the snippet's
      # character budget, truncating real code off the end.
      lead_lines = [] of String
      back_idx = line - 2
      MAX_LEAD_DECORATOR_LINES.times do
        break if back_idx < 0
        stripped = lines[back_idx].strip
        break unless stripped.empty? || stripped.starts_with?("@")

        lead_lines.unshift("#{back_idx + 1}: #{stripped}") unless stripped.empty?
        back_idx -= 1
      end

      start_idx = line - 1
      selected = lead_lines
      brace_depth = 0
      paren_balance = 0
      # Block style starts as `nil` and locks in to one of:
      #   :brace   — JS / Go / Java / Rust / C-family `{ ... }`
      #   :ruby    — Ruby `def name` (ends on a line with `end` at
      #              the same indent as `def`)
      #   :python  — Python `def name():` / `class …:` (ends when a
      #              non-blank line returns to ≤ the def's indent)
      block_style : Symbol? = nil
      # Indent of the `def` / `class` that triggered :python / :ruby
      # mode. We use it to stop the capture when control returns to
      # that column (= the next top-level statement / next decorator).
      def_indent : Int32? = nil

      start_idx.upto(Math.min(start_idx + max_lines - 1, lines.size - 1)) do |idx|
        raw_line = lines[idx]
        line_indent = raw_line.size - raw_line.lstrip.size

        # Indent-based end-of-block check for :python / :ruby. Runs
        # BEFORE we append the line, so we don't bleed into the next
        # function / decorator (the bug behind the django `/public/`
        # false-positive — the next function's `@login_required`
        # decorator was getting captured into the previous handler's
        # scope).
        if (def_idx = def_indent) && (style = block_style)
          if (style == :python || style == :ruby) &&
             !raw_line.strip.empty? && line_indent <= def_idx
            # `end` on a line at def-column belongs to the def — keep
            # it. Anything else at that column is the *next* statement.
            stripped_check = raw_line.strip
            if !(style == :ruby && stripped_check == "end")
              break
            end
          end
        end

        # Blank lines inside the body are skipped for the same reason as
        # the lead-in ones: they add a bare `N: ` placeholder and nothing
        # else. Only the append is skipped — the block-boundary tracking
        # below still sees every line, so brace depth and indent
        # detection are unaffected.
        body_line = raw_line.strip
        selected << "#{idx + 1}: #{body_line}" unless body_line.empty?

        sanitized = raw_line.gsub(/(['"]).*?\1/, "\"\"")
        opens = sanitized.count('{')
        closes = sanitized.count('}')
        brace_depth += opens - closes
        paren_balance += sanitized.count('(') - sanitized.count(')')

        stripped = sanitized.strip
        # Decorator / annotation lines (`@app.route(...)`, `@PostMapping(...)`,
        # `@PreAuthorize(...)`) come *before* the actual route handler.
        # Their trailing `)` is not end-of-statement — the handler is on
        # the next line(s).
        is_decorator = stripped.starts_with?("@")

        # Lock in a block style on the first line that opens one. Once
        # locked, later lines don't change the kind.
        if block_style.nil?
          if opens > 0 || sanitized.matches?(/\bdo\b/)
            block_style = :brace
          elsif !is_decorator && stripped.ends_with?(":")
            block_style = :python
            def_indent = line_indent
          elsif !is_decorator && (stripped.matches?(/\b(def|class)\s+\w+/) || stripped.matches?(/\bfunction\s+\w+/))
            block_style = :ruby
            def_indent = line_indent
          end
        end

        case block_style
        when :brace
          # JS-style: capture until braces close back to zero.
          break if brace_depth <= 0
        when :python
          # Indent guard runs at the top of the next iteration; no
          # per-line break needed here.
        when :ruby
          # Stop after the matching `end` at the def's indent.
          if def_indent == line_indent && stripped == "end"
            break
          end
        else
          statement_done = !is_decorator && (stripped.ends_with?(";") || stripped.ends_with?(")") || stripped.ends_with?(" do"))
          break if statement_done && paren_balance <= 0
        end
      end

      snippet = selected.join(" | ").gsub(/\s+/, " ").strip
      return if snippet.empty?
      snippet = snippet.size > max_chars ? snippet[0, max_chars] : snippet
      @route_scope_cache[cache_key] = snippet
      snippet
    end

    def lines_for(path : String?) : Array(String)
      return [] of String unless path

      read_lines(path).dup
    end

    private def read_lines(path : String) : Array(String)
      if cached = @file_cache[path]?
        return cached
      end

      # The detector already read and cached almost every file of the
      # scan; going back to disk here paid a second open per file the
      # augmentor touches.
      content = CodeLocator.instance.content_for(path) || Noir::TextFile.read(path)
      lines = content.split("\n")
      @file_cache[path] = lines
      lines
    rescue
      [] of String
    end
  end
end
