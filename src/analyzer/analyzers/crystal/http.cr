require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Http < CrystalEngine
    # Precompiled regexes (avoid repeated compilation of interpolated literals inside
    # the per-line hot path; mirrors the VERB_ROUTE_PATTERNS approach in grip.cr).
    METHOD_THEN_PATH_RE = /context\.request\.method\s*(?:==|===)\s*["'](GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']\s*&&\s*.*context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']/
    PATH_THEN_METHOD_RE = /context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']\s*&&\s*.*context\.request\.method\s*(?:==|===)\s*["'](GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']/
    PATH_COMPARE_RE     = /context\.request\.path\s*(?:==|===|\.starts_with\?|\.includes\?)\s*\(?\s*["']([^"']+?)["']/
    WHEN_RE             = /(?:^|[^.\w])when\s+["']([^"']+?)["']/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = [] of String

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          lines << line
        end
      end
      lines = mask_crystal_heredocs(lines)

      last_endpoint : Endpoint? = nil

      # Indent-based tracking for `case ... request.path` (and similar) blocks so that
      # bare `when "/..."` only produces endpoints when it is actually a route guard.
      # This prevents false positives from unrelated `case` statements (e.g. on enums,
      # strings, or other values) that happen to contain path-like literals.
      # Pattern mirrors the namespace/scope indent stacks used in kemal/grip/lucky/etc.
      path_case_stack = [] of Int32

      lines.each_with_index do |line, index|
        raw = line
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line)
        content_for_scan = stripped
        indent = raw.size - raw.lstrip.size

        # Enter a request.path case (common spellings)
        if stripped.lstrip =~ /^case\b.*\brequest\.path\b/ || stripped.lstrip =~ /^case\s+context\.request\.path\b/
          path_case_stack << indent
        end

        # Pop scopes on `end` that dedents to or past the opening case indent.
        unless path_case_stack.empty?
          if end_match = stripped.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            while !path_case_stack.empty? && end_indent <= path_case_stack.last
              path_case_stack.pop
            end
          end
        end

        in_path_case = !path_case_stack.empty?

        endpoint = line_to_endpoint(content_for_scan, in_path_case)
        if !endpoint.method.empty? && valid_crystal_route_path?(endpoint.url)
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          endpoints << endpoint
          last_endpoint = endpoint
        end

        param = line_to_param(stripped)
        unless param.name.empty?
          if le = last_endpoint
            unless le.method.empty?
              le.push_param(param)
            end
          end
        end
      end

      endpoints
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      if match = content.match(/context\.request\.query_params\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "query")
      end
      if match = content.match(/context\.request\.form_params\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "form")
      end
      if match = content.match(/context\.request\.headers\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "header")
      end
      if match = content.match(/context\.request\.cookies\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "cookie")
      end

      Param.new("", "", "")
    end

    # `in_path_case` is only used to gate the unconditional `when` matcher.
    # The explicit `method && path` and `path ==` checks are safe to run unconditionally
    # (they mention the request objects) and are therefore handled the same way inside/outside.
    def line_to_endpoint(content : String, in_path_case : Bool = false) : Endpoint
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # method + path combined on same line (supports the common "if method && path" pattern)
      if match = content.match(METHOD_THEN_PATH_RE)
        return Endpoint.new(normalize_crystal_interpolation(match[2]), match[1])
      end
      if match = content.match(PATH_THEN_METHOD_RE)
        return Endpoint.new(normalize_crystal_interpolation(match[1]), match[2])
      end

      # if/elsif explicit path match (common in handlers)
      if match = content.match(PATH_COMPARE_RE)
        p = match[1]
        if valid_crystal_route_path?(p)
          return Endpoint.new(normalize_crystal_interpolation(p), "GET")
        end
      end

      # `when "/path"` — only when we have positively entered a `case ...request.path` block.
      # This avoids matching unrelated `case` / `when` statements that contain path-like strings
      # (e.g. `case status; when "/foo" ...` or documentation strings that leak past heredoc mask).
      if in_path_case
        if match = content.match(WHEN_RE)
          p = match[1]
          if valid_crystal_route_path?(p)
            return Endpoint.new(normalize_crystal_interpolation(p), "GET")
          end
        end
      end

      Endpoint.new("", "")
    end
  end
end
