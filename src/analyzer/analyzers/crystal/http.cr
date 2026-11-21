require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Http < CrystalEngine
    analyzer_for "crystal_http"

    # Precompiled regexes (avoid repeated compilation of interpolated literals inside
    # the per-line hot path; mirrors the VERB_ROUTE_PATTERNS approach in grip.cr).
    METHOD_THEN_PATH_RE = /context\.request\.method\s*(?:==|===)\s*["'](GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']\s*&&\s*.*context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']/
    PATH_THEN_METHOD_RE = /context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']\s*&&\s*.*context\.request\.method\s*(?:==|===)\s*["'](GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']/
    # An exact compare only: `path.starts_with?("/api/")` guards a subtree
    # and `includes?` a substring, neither of which is a route.
    PATH_COMPARE_RE = /context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']/
    WHEN_RE         = /(?:^|[^.\w])when\s+((?:"[^"]*"|'[^']*')(?:\s*,\s*(?:"[^"]*"|'[^']*'))*)(?=\s*(?:,|;|then\b|$))/
    WHEN_LITERAL_RE = /"([^"]*)"|'([^']*)'/
    PATH_CASE_RE    = /(?:^\s*|[=(]\s*|\breturn\s+)(case)\b.*\brequest\.path\b/
    PATH_BRANCH_RE  = /^\s*(?:when|else)\b/
    # The handler's argument goes by any name (`HTTP::Server.new do |ctx|`,
    # `def call(ctx)`, or `ctx = context` inside one). The patterns above
    # read it as `context`, so those names are rewritten to it first. Only a
    # handler's own argument: `ctx.request.path == "/x"` in a Kemal helper
    # taking the context is a guard, not a route.
    HANDLER_ARG_RE   = /HTTP::Server\.new\b[^|]*\|\s*(\w+)|\bdef\s+call\s*\(\s*(\w+)/
    HANDLER_ALIAS_RE = /^\s*(\w+)\s*=\s*(\w+)\s*$/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      lines = mask_crystal_heredocs(read_file_content(path).lines)

      last_endpoints = [] of Endpoint

      # Indent-based tracking for `case ... request.path` (and similar) blocks so that
      # bare `when "/..."` only produces endpoints when it is actually a route guard.
      # This prevents false positives from unrelated `case` statements (e.g. on enums,
      # strings, or other values) that happen to contain path-like literals.
      # Pattern mirrors the namespace/scope indent stacks used in kemal/grip/lucky/etc.
      path_case_stack = [] of NamedTuple(indent: Int32, column: Int32, branch_indent: Int32?)
      lines = as_context_receiver(lines)
      param_lines = crystal_param_lines(lines)

      lines.each_with_index do |line, index|
        raw = line
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line)
        indent = raw.size - raw.lstrip.size

        # Enter a request.path case, as a statement or as a value
        # (`body = case ctx.request.path`, `return case ...`, `print(case ...`).
        # Its `end` sits under `case` (formatter layout) or at the line's
        # indent, so the scope keeps both columns. A case that also ends on
        # this line closes once the line is scanned.
        one_line_case = false
        if stripped.includes?("case") && (case_match = stripped.match(PATH_CASE_RE))
          case_column = case_match.begin(1)
          path_case_stack << {indent: indent, column: case_column, branch_indent: nil}
          one_line_case = stripped[case_column..].matches?(END_WORD_RE)
        end

        # Pop scopes on an `end` under their `case`, or dedented to or past
        # the line that opened them.
        unless path_case_stack.empty?
          if end_match = stripped.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            while (open_case = path_case_stack.last?) &&
                  (end_indent == open_case[:column] || end_indent <= open_case[:indent])
              path_case_stack.pop
              last_endpoints.clear if last_endpoints.size > 1
            end
          end
        end

        if (open_case = path_case_stack.last?) && stripped.matches?(PATH_BRANCH_RE)
          same_level = if branch_indent = open_case[:branch_indent]
                         indent == branch_indent
                       else
                         indent == open_case[:indent] || indent == open_case[:column]
                       end
          if same_level
            path_case_stack[-1] = {indent: open_case[:indent], column: open_case[:column], branch_indent: indent}
            last_endpoints.clear
          end
        end

        line_endpoints = line_to_endpoints(stripped, !path_case_stack.empty?)
        path_case_stack.pop if one_line_case
        line_endpoints.select! { |endpoint| valid_crystal_route_path?(endpoint.url) }
        unless line_endpoints.empty?
          details = Details.new(PathInfo.new(path, index + 1))
          line_endpoints.map! do |endpoint|
            endpoint.details = details
            endpoint
          end
          endpoints.concat(line_endpoints)
          last_endpoints = line_endpoints
        end

        param = line_to_param(param_lines[index])
        unless param.name.empty?
          last_endpoints.each { |endpoint| endpoint.push_param(param) }
        end
        last_endpoints.clear if one_line_case && last_endpoints.size > 1
      end

      endpoints
    end

    # `lines` with each handler argument's `<name>.request.` read as
    # `context.request.`.
    private def as_context_receiver(lines : Array(String)) : Array(String)
      # A `Kemal::Handler#call(env)` is middleware: its path compares are guards.
      kemal_middleware = lines.any?(&.includes?("Kemal::Handler"))
      names = Set(String).new
      lines.each do |line|
        next if !line.includes?("HTTP::Server") && !line.includes?("call") && (names.empty? || !line.includes?('='))
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line)
        if match = stripped.match(HANDLER_ARG_RE)
          names << (match[1]? || match[2]) unless kemal_middleware && match[1]?.nil?
        elsif (match = stripped.match(HANDLER_ALIAS_RE)) && names.includes?(match[2])
          names << match[1]
        end
      end
      names.delete("context")
      return lines if names.empty?

      receiver = /\b(?<![.@:])(?:#{names.map { |name| Regex.escape(name) }.join('|')})\.request\./
      lines.map { |line| line.includes?(".request.") ? line.gsub(receiver, "context.request.") : line }
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # HTTP::Server param accessors all live under `context.request.`;
      # skip four PCRE2 scans when the prefix is absent.
      return Param.new("", "", "") unless content.includes?("context.request.")

      if content.includes?("query_params") && (match = content.match(/context\.request\.query_params\[[^\]]*["']([^"'\]]+)["']/))
        return Param.new(match[1], "", "query")
      end
      if content.includes?("form_params") && (match = content.match(/context\.request\.form_params\[[^\]]*["']([^"'\]]+)["']/))
        return Param.new(match[1], "", "form")
      end
      if content.includes?("headers") && (match = content.match(/context\.request\.headers\[[^\]]*["']([^"'\]]+)["']/))
        return Param.new(match[1], "", "header")
      end
      if content.includes?("cookies") && (match = content.match(/context\.request\.cookies\[[^\]]*["']([^"'\]]+)["']/))
        return Param.new(match[1], "", "cookie")
      end

      Param.new("", "", "")
    end

    # `in_path_case` is only used to gate the unconditional `when` matcher.
    # The explicit `method && path` and `path ==` checks are safe to run unconditionally
    # (they mention the request objects) and are therefore handled the same way inside/outside.
    private def line_to_endpoints(content : String, in_path_case : Bool) : Array(Endpoint)
      # No string literal ⇒ no path to extract. Also skip heavy combined
      # method/path regexes unless the request objects appear.
      has_quote = content.includes?('"') || content.includes?("'")
      return [] of Endpoint unless has_quote

      if content.includes?("request.method") && content.includes?("request.path")
        # method + path combined on same line (supports the common "if method && path" pattern)
        if match = content.match(METHOD_THEN_PATH_RE)
          return [Endpoint.new(normalize_crystal_interpolation(match[2]), match[1])]
        end
        if match = content.match(PATH_THEN_METHOD_RE)
          return [Endpoint.new(normalize_crystal_interpolation(match[1]), match[2])]
        end
      end

      # if/elsif explicit path match (common in handlers)
      if content.includes?("request.path") && (match = content.match(PATH_COMPARE_RE))
        p = match[1]
        if valid_crystal_route_path?(p)
          return [Endpoint.new(normalize_crystal_interpolation(p), "GET")]
        end
      end

      # `when "/path", "/alias"` — only in a `case ...request.path` block.
      # This avoids matching unrelated `case` / `when` statements that contain path-like strings
      # (e.g. `case status; when "/foo" ...` or documentation strings that leak past heredoc mask).
      if in_path_case && content.includes?("when") && (match = content.match(WHEN_RE))
        return match[1].scan(WHEN_LITERAL_RE).compact_map do |literal|
          p = literal[1]? || literal[2]
          Endpoint.new(normalize_crystal_interpolation(p), "GET") if valid_crystal_route_path?(p)
        end
      end

      [] of Endpoint
    end
  end
end
