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

  # Tornado auth decorators. A `get_current_user` override only computes
  # `current_user`; `@tornado.web.authenticated` is what refuses.
  TORNADO_PATTERNS = [
    {/\@(?:tornado\.)?web\.authenticated\b/, "Tornado @authenticated decorator"},
    {/\@authenticated/, "Tornado @authenticated"},
  ]

  # Litestar's own guard mechanism: `guards=[fn]` on a route decorator, or
  # `guards = [fn]` on the Controller. An empty list guards nothing.
  LITESTAR_GUARDS_RE = /\bguards\s*=\s*\[\s*([A-Za-z_][\w.]*)/

  def self.target_techs : Array(String)
    ["python_sanic", "python_tornado", "python_litestar"]
  end

  private def check_endpoint(endpoint : Endpoint)
    # A Tornado route sits in a handler list; the method it dispatches to,
    # when the analyzer resolved it, carries the decorators.
    if endpoint.details.technology == "python_tornado" && (handler = endpoint.handler)
      if description = handler_decorator_guard(handler)
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "python_misc_auth"))
      end
      return
    end
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
        call = route_call(lines, line_idx)
        if guard = litestar_guard(lines, line_idx, call)
          endpoint.add_tag(Tag.new("auth", "Protected by Litestar guards=[#{guard}]", "python_misc_auth"))
          return
        end
        if backend = litestar_backend_guard(endpoint, path_info.path, call)
          endpoint.add_tag(Tag.new("auth", "Protected by #{backend}", "python_misc_auth"))
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
    end
  end

  private def handler_decorator_guard(handler : Handler) : String?
    lines = read_file_lines(handler.path || return) || return
    idx = (handler.line || return) - 2
    while idx >= 0 && (current = lines[idx].strip).starts_with?('@')
      TORNADO_PATTERNS.each { |pattern, desc| return desc if current.matches?(pattern) }
      idx -= 1
    end
    nil
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

  # The route decorator call at `route_idx`, joined across lines.
  private def route_call(lines : Array(String), route_idx : Int32) : String
    call = lines[route_idx]
    depth = bracket_balance(call)
    idx = route_idx + 1
    while depth > 0 && idx < lines.size && idx < route_idx + 30
      call += lines[idx]
      depth += bracket_balance(lines[idx])
      idx += 1
    end
    call
  end

  # A Litestar auth backend (`auth = JWTAuth[User](..., exclude=[...])`)
  # registered on the app through `auth.on_app_init` or `auth.middleware`
  # puts its middleware in front of every route of that app. It lets a
  # request through when the path matches an `exclude` pattern anywhere
  # (Litestar joins them into one regex and `findall`s the path), when the
  # route's opt carries `exclude_opt_key` (`exclude_from_auth=True`), or for
  # an `exclude_http_methods` verb (OPTIONS and HEAD by default).
  LITESTAR_AUTH_BACKEND = /^([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*(?:[\w.]+\.)?(JWTAuth|JWTCookieAuth|OAuth2PasswordBearerAuth|SessionAuth)\b/
  PY_MANIFEST           = /\A(?:pyproject\.toml|setup\.py|setup\.cfg)\z/
  PY_STRING             = /[rbu]?(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')/

  private record LitestarBackend, name : String, kind : String, exclude : Array(Regex), opt_key : String, methods : Array(String)

  @litestar_backends : Hash(String?, Array(LitestarBackend))? = nil

  private def litestar_backend_guard(endpoint : Endpoint, path : String, call : String) : String?
    backends = litestar_backends[nearest_project_root(path, PY_MANIFEST)]? || return
    url = endpoint.url.sub(/\A[a-zA-Z][\w+.-]*:\/\/[^\/]*/, "")
    backends.each do |backend|
      next if backend.methods.includes?(endpoint.method.upcase)
      key = Regex.escape(backend.opt_key)
      next if call.matches?(/\b#{key}\s*=\s*True\b|["']#{key}["']\s*:\s*True\b/)
      next if backend.exclude.any?(&.matches?(url))
      return "Litestar #{backend.kind} #{backend.name} (outside its exclude paths)"
    end
    nil
  end

  # The wired auth backends of each project root.
  private def litestar_backends : Hash(String?, Array(LitestarBackend))
    @litestar_backends ||= begin
      found = Hash(String?, Array(LitestarBackend)).new
      sources = collect_files_by_extension(".py").compact_map { |file| read_file(file).try { |content| {file, content} } }
      sources.each do |file, content|
        next unless content.includes?("Auth")
        lines = content.lines
        lines.each_with_index do |line, idx|
          m = line.match(LITESTAR_AUTH_BACKEND) || next
          root = nearest_project_root(file, PY_MANIFEST)
          wired = /\b#{Regex.escape(m[1])}\.(?:on_app_init|middleware)\b/
          next unless sources.any? { |other, text| text.matches?(wired) && nearest_project_root(other, PY_MANIFEST) == root }
          if backend = litestar_backend(m[1], m[2], route_call(lines, idx))
            (found[root] ||= [] of LitestarBackend) << backend
          end
        end
      end
      found
    end
  end

  # nil when an `exclude` the scan cannot read (a name, a pattern this
  # regex engine rejects) leaves the open paths unknown.
  private def litestar_backend(name : String, kind : String, statement : String) : LitestarBackend?
    exclude = [] of Regex
    if m = statement.match(/\bexclude\s*=\s*/)
      value = m.post_match
      literal = value.match(/\A\[[^\]]*\]/) || value.match(/\A#{PY_STRING.source}/) || return
      literal[0].scan(PY_STRING) do |item|
        exclude << (Regex.new(item[1]? || item[2]? || "") rescue return)
      end
    end
    opt_key = statement.match(/\bexclude_opt_key\s*=\s*["'](\w+)["']/).try(&.[1]) || "exclude_from_auth"
    methods = %w[OPTIONS HEAD]
    if m = statement.match(/\bexclude_http_methods\s*=\s*/)
      value = m.post_match.match(/\A[\[(][^\])]*[\])]|\ANone\b/) || return
      methods = value[0].scan(/["'](\w+)["']/).map(&.[1].upcase)
    end
    LitestarBackend.new(name, kind, exclude, opt_key, methods)
  end

  # The guard named by the route decorator call `call` at `route_idx`,
  # else by the enclosing Controller's `guards` attribute.
  private def litestar_guard(lines : Array(String), route_idx : Int32, call : String) : String?
    if m = call.match(LITESTAR_GUARDS_RE)
      return m[1]
    end

    route_indent = lines[route_idx].size - lines[route_idx].lstrip.size
    return if route_indent == 0
    idx = route_idx - 1
    while idx >= 0
      line = lines[idx]
      stripped = line.lstrip
      indent = line.size - stripped.size
      if !stripped.empty? && !stripped.starts_with?('#') && indent < route_indent
        return unless stripped.starts_with?("class ")
        body = idx + 1
        while body < lines.size
          body_line = lines[body]
          body_stripped = body_line.lstrip
          break if !body_stripped.empty? && !body_stripped.starts_with?('#') && body_line.size - body_stripped.size <= indent
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
end
