require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "python_misc_auth", name: "Python Misc Auth Tagger", desc: "Identifies Sanic/Tornado/Litestar authentication patterns", order: 110)]
class PythonMiscAuthTagger < FrameworkTagger
  # Sanic auth patterns
  SANIC_PATTERNS = [
    {/\@authorized\s*\(/, "Sanic @authorized decorator"},
    {/\@protected\s*\(/, "Sanic @protected decorator"},
    {/\@scoped\s*\(/, "Sanic @scoped decorator"},
    {/sanic_jwt/, "Sanic JWT"},
    {/\@auth\.login_required/, "Sanic auth login_required"},
  ]

  # Tornado auth patterns. These are scanned only in the decorator window
  # above a handler, so they must be decorators. The body/class signals
  # (`self.current_user`, a `def get_current_user` override) are handled
  # separately by `check_class_auth`; a bare `current_user` / a
  # `get_current_user(` *call* in the decorator window is not an auth
  # decorator and only produced false positives, so they're omitted here.
  TORNADO_PATTERNS = [
    {/\@tornado\.web\.authenticated/, "Tornado @authenticated decorator"},
    {/\@authenticated/, "Tornado @authenticated"},
  ]

  # Litestar's own guard mechanism: `guards=[fn]` on a route decorator, or
  # `guards = [fn]` on the Controller. An empty list guards nothing.
  LITESTAR_GUARDS_RE = /\bguards\s*=\s*\[\s*([A-Za-z_][\w.]*)/

  def self.target_techs : Array(String)
    ["python_sanic", "python_tornado", "python_litestar"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      if endpoint.details.technology == "python_litestar"
        if guard = litestar_guard(lines, line_idx)
          endpoint.add_tag(Tag.new("auth", "Protected by Litestar guards=[#{guard}]", "python_misc_auth"))
          return
        end
        next
      end

      # Check decorators above function/method
      description = check_decorators(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "python_misc_auth"))
        return
      end

      # Check class for Tornado auth mixin/method
      description = check_class_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "python_misc_auth"))
        return
      end
    end
  end

  private def check_decorators(lines : Array(String), func_line : Int32) : String?
    all_patterns = SANIC_PATTERNS + TORNADO_PATTERNS
    # A Sanic route's line is its `@app.route` decorator, and the auth
    # decorators that wrap the handler (`@protected()`) sit below it.
    annotation_lines_below(lines, func_line, "@").each do |current|
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    idx = func_line - 1
    while idx >= 0 && idx >= func_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < func_line - 1

      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx -= 1
    end
    nil
  end

  # The guard named by the route decorator at `route_idx` (its call may
  # span lines), else by the enclosing Controller's `guards` attribute.
  private def litestar_guard(lines : Array(String), route_idx : Int32) : String?
    call = lines[route_idx]
    depth = bracket_balance(call)
    idx = route_idx + 1
    while depth > 0 && idx < lines.size && idx < route_idx + 30
      call += lines[idx]
      depth += bracket_balance(lines[idx])
      idx += 1
    end
    if m = call.match(LITESTAR_GUARDS_RE)
      return m[1]
    end

    route_indent = lines[route_idx].size - lines[route_idx].lstrip.size
    idx = route_idx - 1
    while idx >= 0
      line = lines[idx]
      stripped = line.lstrip
      indent = line.size - stripped.size
      if !stripped.empty? && indent < route_indent
        return unless stripped.starts_with?("class ")
        body = idx + 1
        while body < lines.size
          body_line = lines[body]
          body_stripped = body_line.lstrip
          break if !body_stripped.empty? && body_line.size - body_stripped.size <= indent
          if body_line.size - body_stripped.size == route_indent && (m = body_stripped.match(/\Aguards\s*(?::[^=]+)?=\s*\[\s*([A-Za-z_][\w.]*)/))
            return m[1]
          end
          body += 1
        end
        return
      end
      idx -= 1
    end
    nil
  end

  private def check_class_auth(lines : Array(String), method_line : Int32) : String?
    # Walk backwards to find class definition with Tornado's get_current_user override
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.starts_with?("class ")
        # Found class — scan class body for get_current_user
        scan_idx = idx + 1
        while scan_idx < lines.size && scan_idx < idx + 30
          scan_line = lines[scan_idx].strip
          break if scan_line.starts_with?("class ")

          if scan_line.includes?("def get_current_user")
            return "Tornado get_current_user override"
          end

          scan_idx += 1
        end
        break
      end

      idx -= 1
    end
    nil
  end
end
