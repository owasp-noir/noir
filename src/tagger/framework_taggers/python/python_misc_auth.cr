require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./python_auth_access"

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
      found = handler_decorator_guards(handler)
      tornado_class_layers(handler).each { |fragment| found << {nil, fragment} } if found.any?(&.[0])
      add_decorator_guards(endpoint, found, handler.path.to_s)
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
        if backend = litestar_backend_guard(endpoint, path_info.path, call, lines, line_idx)
          endpoint.add_tag(Tag.new("auth", "Protected by #{backend}", "python_misc_auth"))
          return
        end
        next
      end

      # Check decorators above function/method
      found = check_decorators(lines, line_idx)
      if found.any?(&.[0])
        add_decorator_guards(endpoint, found, path_info.path)
        return
      end
    end
  end

  # The layers found, as `{description, line}`: the first guard names the
  # tag and every layer adds what it requires. A layer with no description
  # is one the tagger does not judge (another decorator, a `prepare`): what
  # it checks is unread.
  private def add_decorator_guards(endpoint : Endpoint, found : Array({String?, String}), file : String)
    first = found.compact_map(&.[0]).first? || return
    requires = found.flat_map do |description, line|
      cnf = description ? line_access(line, description, file, endpoint.method) : PythonAuthAccess.unresolved(line.lchop('@'))
      Access.clauses(cnf, line.lchop('@'))
    end
    endpoint.add_tag(Tag.new("auth", "Protected by #{first}", "python_misc_auth", requires: requires.uniq!))
  end

  TORNADO_HANDLER_BASE = /\A(?:tornado\.)?(?:web\.)?RequestHandler\z/

  # The handler class and the project bases it inherits: an overridden
  # `prepare` or `initialize` runs ahead of every verb method, and a base
  # the scan does not hold is not read either way.
  private def tornado_class_layers(handler : Handler) : Array(String)
    found = [] of String
    queue = [{handler.path.to_s, handler.name.rpartition('.')[0]}]
    seen = Set(Tuple(String, String)).new
    while (node = queue.shift?) && seen.size < 8
      next if node[1].empty? || !seen.add?(node)
      file, name = node
      lines = read_file_lines(file) || [] of String
      header = lines.index { |line| line.match(/\Aclass\s+([A-Za-z_]\w*)/).try(&.[1]) == name }
      unless header
        found << "class #{name}"
        next
      end
      lines[(header + 1)..].each do |line|
        break unless line.blank? || line[0].ascii_whitespace?
        if m = line.match(/\A\s+(?:async\s+)?def\s+(prepare|initialize)\b/)
          found << "#{name}.#{m[1]}"
        end
      end
      bases = lines[header].match(/\Aclass\s+\w+\s*\(([^)]*)\)/).try(&.[1]).to_s.split(',').map(&.strip)
      bases.each do |base|
        next if base.empty? || base.includes?('=') || base.matches?(TORNADO_HANDLER_BASE)
        if site = python_definition_site(file, base)
          queue << site
        else
          found << "base #{base} of #{name}"
        end
      end
    end
    found
  end

  # What a matched line requires: Tornado's `authenticated` and sanic-jwt's
  # `protected` / `scoped` where `file` binds the name to them; anything
  # else is a guard whose check noir did not read.
  private def line_access(line : String, description : String, file : String, method : String) : Access::CNF
    unread = DjangoAccess.unread(description)
    return unread unless line.starts_with?('@')
    name, args, source = DjangoAccess.call(line) || return unread
    head, _, leaf = name.rpartition('.')
    imports = from_imports(file)
    qualified = head.empty? ? imports[name]? : "#{imports[head]? || head}.#{leaf}"
    case qualified
    when "tornado.web.authenticated"
      # Redirects a GET or HEAD to the login URL and answers anything else
      # 403 while `current_user` is unset; no verb is exempt.
      PythonAuthAccess.signed_in
    when "sanic_jwt.scoped"
      PythonAuthAccess.scoped(args, source, custom_scope_validator?, method)
    else
      qualified.try { |found| PythonAuthAccess.library_decorator(found, args, source, method) } || unread
    end
  end

  @from_imports = Hash(String, Hash(String, String)).new

  private def from_imports(path : String) : Hash(String, String)
    @from_imports[path] ||= PythonAuthAccess.from_imports(read_file(path) || "")
  end

  @custom_scope_validator : Bool? = nil

  # Whether a sanic-jwt `Initialize` in the scan may replace the scope
  # check (`override_scope_validator`, `destructure_scopes`).
  private def custom_scope_validator? : Bool
    if (known = @custom_scope_validator).nil?
      known = @custom_scope_validator = collect_files_by_extension(".py").any? do |file|
        !!CodeLocator.instance.read_source(file).try(&.matches?(/\b(?:override_scope_validator|destructure_scopes)\b/))
      end
    end
    known
  end

  # The decorators stacked above the handler's `def`, read upward past a
  # comment line or a decorator's wrapped arguments.
  private def handler_decorator_guards(handler : Handler) : Array({String?, String})
    found = [] of {String?, String}
    lines = read_file_lines(handler.path || return found) || return found
    idx = (handler.line || return found) - 2
    open = 0
    while idx >= 0
      current = lines[idx].strip
      idx -= 1
      next if current.starts_with?('#')
      open -= bracket_balance(current)
      next if open > 0
      break unless current.starts_with?('@')
      found << (matched(TORNADO_PATTERNS, current) || {nil, current})
    end
    found
  end

  # The guard lines of the first window that holds one: the decorators
  # below the route line, else the lines above it.
  # Below the route line every decorator wraps the handler, so one that is
  # not a guard pattern nor another route is kept as unread.
  private def check_decorators(lines : Array(String), func_line : Int32) : Array({String?, String})
    all_patterns = SANIC_PATTERNS + TORNADO_PATTERNS
    # A Sanic route's line is its `@app.route` decorator, and the auth
    # decorators that wrap the handler (`@protected()`) sit below it.
    found = annotation_lines_below(lines, func_line, "@").compact_map do |current|
      matched(all_patterns, current) || ({nil, current} if current.starts_with?('@') && !current.matches?(SANIC_ROUTE))
    end
    return found if found.any?(&.[0])
    found.clear

    idx = func_line - 1
    while idx >= 0 && idx >= func_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < func_line - 1

      matched(all_patterns, current).try { |hit| found << hit }

      idx -= 1
    end
    found
  end

  SANIC_ROUTE = /\A@[\w.]+\.(?:route|get|post|put|patch|delete|head|options|websocket)\s*\(/

  private def matched(patterns : Array({Regex, String}), line : String) : {String?, String}?
    patterns.each { |pattern, desc| return {desc, line} if line.matches?(pattern) }
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
  # route's opt (its own or its Controller's) carries `exclude_opt_key`
  # (`exclude_from_auth=True`), or for an `exclude_http_methods` verb
  # (OPTIONS and HEAD by default; `None` leaves the middleware's OPTIONS).
  LITESTAR_AUTH_BACKEND = /^([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*(?:[\w.]+\.)?(JWTAuth|JWTCookieAuth|OAuth2PasswordBearerAuth|SessionAuth)\b/
  PY_STRING             = /[rbu]?(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')/

  # `scope`: the directory holding the backend and every file wiring it,
  # the app it guards.
  private record LitestarBackend, name : String, kind : String, exclude : Array(Regex), opt_key : String, methods : Array(String), scope : String

  @litestar_backends : Array(LitestarBackend)? = nil

  private def litestar_backend_guard(endpoint : Endpoint, path : String, call : String, lines : Array(String), route_idx : Int32) : String?
    file = File.expand_path(path)
    url = endpoint.url.sub(/\A[a-zA-Z][\w+.-]*:\/\/[^\/]*/, "")
    litestar_backends.each do |backend|
      next unless file.starts_with?(backend.scope)
      next if backend.methods.includes?(endpoint.method.upcase)
      key = Regex.escape(backend.opt_key)
      opt = /\b#{key}\s*=\s*True\b|["']#{key}["']\s*:\s*True\b/
      next if call.matches?(opt) || controller_attribute(lines, route_idx, "opt").try(&.matches?(opt))
      next if backend.exclude.any?(&.matches?(url))
      return "Litestar #{backend.kind} #{backend.name} (outside its exclude paths)"
    end
    nil
  end

  # The auth backends some file wires into an app: the file declaring the
  # backend, or one importing it from there, references `.on_app_init` or
  # `.middleware` on it.
  private def litestar_backends : Array(LitestarBackend)
    @litestar_backends ||= begin
      found = [] of LitestarBackend
      sources = collect_files_by_extension(".py").compact_map { |file| read_file(file).try { |content| {file, content} } }
      sources.each do |file, content|
        next unless content.includes?("Auth")
        lines = content.lines
        lines.each_with_index do |line, idx|
          m = line.match(LITESTAR_AUTH_BACKEND) || next
          wired = /\b#{Regex.escape(m[1])}\.(?:on_app_init|middleware)\b/
          wiring = sources.compact_map do |other, text|
            next unless text.matches?(wired)
            other if other == file || python_imported_symbols(other)[m[1]]?.try(&.[0]) == file
          end
          next if wiring.empty?
          if backend = litestar_backend(m[1], m[2], route_call(lines, idx), common_dir([file] + wiring))
            found << backend
          end
        end
      end
      found
    end
  end

  private def common_dir(files : Array(String)) : String
    parts = files.map { |file| File.dirname(File.expand_path(file)).split('/') }
    shared = parts.first.each_with_index.take_while { |part, i| parts.all? { |other| other[i]? == part } }.map(&.[0]).to_a
    shared.join('/') + '/'
  end

  # nil when an `exclude` the scan cannot read (a name, a pattern this
  # regex engine rejects) leaves the open paths unknown.
  private def litestar_backend(name : String, kind : String, statement : String, scope : String) : LitestarBackend?
    exclude = [] of Regex
    if m = statement.match(/\bexclude\s*=\s*/)
      patterns = string_literals(m.post_match) || return
      patterns.each { |pattern| exclude << (Regex.new(pattern) rescue return) }
    end
    opt_key = statement.match(/\bexclude_opt_key\s*=\s*["'](\w+)["']/).try(&.[1]) || "exclude_from_auth"
    methods = %w[OPTIONS HEAD]
    if m = statement.match(/\bexclude_http_methods\s*=\s*/)
      methods = m.post_match.starts_with?("None") ? %w[OPTIONS] : (string_literals(m.post_match) || return).map(&.upcase)
    end
    LitestarBackend.new(name, kind, exclude, opt_key, methods, scope)
  end

  # The strings of the literal `text` opens with: one string, or a list or
  # tuple of them, read past brackets inside the strings. nil for anything
  # else (a name, a comprehension).
  private def string_literals(text : String) : Array(String)?
    if single = text.match(/\A#{PY_STRING.source}/)
      return [single[1]? || single[2]? || ""]
    end
    close = {'[' => ']', '(' => ')'}[text[0]?]? || return
    items = [] of String
    rest = text[1..]
    loop do
      rest = rest.lstrip
      return items if rest.starts_with?(close)
      m = rest.match(/\A#{PY_STRING.source}\s*(?:,|(?=[\])]))/) || return
      items << (m[1]? || m[2]? || "")
      rest = m.post_match
    end
  end

  # The guard named by the route decorator call `call` at `route_idx`,
  # else by the enclosing Controller's `guards` attribute.
  private def litestar_guard(lines : Array(String), route_idx : Int32, call : String) : String?
    if m = call.match(LITESTAR_GUARDS_RE)
      return m[1]
    end
    controller_attribute(lines, route_idx, "guards").try(&.match(/\Aguards\s*(?::[^=]+)?=\s*\[\s*([A-Za-z_][\w.]*)/)).try(&.[1])
  end

  # The `name = ...` statement in the body of the class enclosing the route
  # at `route_idx`, joined across lines.
  private def controller_attribute(lines : Array(String), route_idx : Int32, name : String) : String?
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
          if body_line.size - body_stripped.size == route_indent && body_stripped.matches?(/\A#{name}\s*(?::[^=]+)?=/)
            return route_call(lines, body).strip
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
