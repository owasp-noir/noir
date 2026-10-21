require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../analyzer/analyzers/python/python_helper"

@[Noir::TaggerFor(key: "flask_auth", name: "Flask Auth Tagger", desc: "Identifies Flask authentication patterns (flask-login, flask-jwt, flask-httpauth)", order: 90)]
class FlaskAuthTagger < FrameworkTagger
  DECORATOR_PATTERNS = [
    {/\@login_required/, "flask-login login_required"},
    {/\@roles_required\s*\(/, "flask-security roles_required"},
    {/\@roles_accepted\s*\(/, "flask-security roles_accepted"},
    # `\b` matches both the bare `@jwt_required` and the `@jwt_required()`
    # call form, both idiomatic in flask-jwt-extended.
    {/\@jwt_required\b/, "flask-jwt-extended jwt_required"},
    {/\@jwt_optional\s*\(/, "flask-jwt-extended jwt_optional"},
    {/\@fresh_jwt_required\s*\(/, "flask-jwt-extended fresh_jwt_required"},
    {/\@auth_required\s*\(/, "flask-security auth_required"},
    {/\@http_auth_required\b/, "flask-security http_auth_required"},
    {/\@token_auth_required\b/, "flask-security token_auth_required"},
    {/\@permission_required\s*\(/, "flask-security/principal permission_required"},
    {/\@auth\.login_required/, "flask-httpauth login_required"},
    {/\@auth\.verify_password/, "flask-httpauth verify_password"},
    {/\@token_auth\.login_required/, "flask-httpauth token_auth"},
    {/\@multi_auth\.login_required/, "flask-httpauth multi_auth"},
    {/\@requires_auth/, "requires_auth"},
    {/\@authenticated/, "authenticated"},
  ]

  DECORATOR_NAME  = /^@([A-Za-z_][\w.]*)/
  ROUTE_DECORATOR = /^@[\w.]+\.(?:route|get|post|put|patch|delete)\s*\(/
  TOP_LEVEL_DEF   = /^(?:async\s+)?def\s+(\w+)/
  CLASS_DEF       = /^class\s+(\w+)\s*(?:\((.*)\))?\s*:/
  # flask-restx `Resource.method_decorators`, Flask `View.decorators`.
  CLASS_DECORATORS = /^\s+(?:method_decorators|decorators)\s*(?::[^=]+)?=([^=].*)/
  # A function a body calls, or a decorator it applies to a nested `def`.
  CALLEE    = /@([A-Za-z_]\w*)|(?<![\w.])([A-Za-z_]\w*)\s*\(/
  DOCSTRING = /"""[\s\S]*?"""|'''[\s\S]*?'''/
  PY_STRING = /"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/

  # What makes a decorator definition an auth guard: it answers 401 in any
  # spelling, or it reads a credential off the request and turns the request
  # away (Dify's inner-API key check answers 404), or it reads the logged-in
  # caller and denies with 403. A 403 alone is not enough: Dify's
  # `email_password_login_enabled` aborts 403 on a feature flag, which says
  # nothing about the caller.
  UNAUTHENTICATED    = /\braise\s+(?:\w+\.)*\w*(?:Unauthori[sz]ed|Unauthenticated|NotAuthenticated|AuthenticationFailed)(?:Error|Exception)?\b|\babort\s*\(\s*(?:401\b|(?:\w+\.)*UNAUTHORIZED\b)|\.unauthorized\s*\(|\breturn\b.*,\s*401\b|\bstatus(?:_code)?\s*=\s*401\b|\bHTTP_401_UNAUTHORIZED\b/
  REQUEST_CREDENTIAL = /\brequest\.(?:authorization\b|(?:headers|cookies|args)(?:\.get\s*\(|\[)\s*["'][\w-]*(?:key|token|auth|secret|signature|password|session)[\w-]*["'])/i
  REJECTION          = /\braise\s+[A-Za-z_]|\babort\s*\(|\breturn\b.*,\s*4\d\d\b/
  CALLER_IDENTITY    = /\bcurrent_user\b|\bis_authenticated\b|\bg\.user\b/
  FORBIDDEN          = /\braise\s+(?:\w+\.)*\w*(?:Forbidden|PermissionDenied|AccessDenied)\w*\b|\babort\s*\(\s*(?:403\b|(?:\w+\.)*FORBIDDEN\b)|\breturn\b.*,\s*403\b/

  def self.target_techs : Array(String)
    ["python_flask"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @python_defs = Hash(String, Hash(String, String)).new
    @verdicts = Hash(Tuple(String, String), Bool).new
    @class_decorators = Hash(Tuple(String, String), Tuple(String, Array(String))?).new
  end

  private def check_endpoint(endpoint : Endpoint)
    if desc = handler_guard(endpoint)
      endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "flask_auth"))
      return
    end

    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walk below with IndexError.
      next if line_num < 1 || line_num > lines.size

      # The line is normally the `@app.route` decorator itself. Flask
      # registers whatever function the route decorator receives, so only
      # the decorators *below* it wrap the registered view: `@login_required`
      # above `@app.route` leaves the route open (Flask's docs say the route
      # decorator must be outermost). Read the stack below and nothing above.
      route_idx = line_num - 1
      if lines[route_idx].strip.starts_with?('@')
        annotation_lines_below(lines, route_idx, "@").each do |current|
          if desc = decorator_guard(current, path_info.path)
            endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "flask_auth"))
            return
          end
        end
        next
      end

      # Otherwise the line is the view itself: walk back over its decorators.
      # 8-line window: Flask decorators stack above def, typically 1-5 decorators
      idx = line_num - 2 # 0-indexed, one line before
      while idx >= 0 && idx >= line_num - 10
        current = lines[idx].strip
        break if current.empty? && idx < line_num - 2

        if current.starts_with?('@') && (desc = decorator_guard(current, path_info.path))
          endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "flask_auth"))
          return
        end

        idx -= 1
      end
    end
  end

  # The guard on the handler the analyzer resolved, outermost first: for a
  # flask-restx Resource or Flask MethodView method, the class's
  # `method_decorators` / `decorators` (inherited from a base class when the
  # class does not set them, as Dify's `WebApiResource` subclasses do), then
  # the decorators stacked on the `def`, top down.
  private def handler_guard(endpoint : Endpoint) : String?
    handler = endpoint.handler || return
    file = handler.path || return
    def_idx = (handler.line || return) - 1
    lines = read_file_lines(file) || return
    return unless 0 <= def_idx < lines.size
    decorators = [] of Tuple(String, String)
    class_name = handler.name.rpartition('.')[0]
    if !class_name.empty? && (found = class_decorators(file, class_name))
      found[1].each { |name| decorators << {"@#{name}", found[0]} }
    end
    decorators_above(lines, def_idx).reverse_each { |line| decorators << {line, file} }
    decorators.each do |line, declaring_file|
      if desc = decorator_guard(line, declaring_file)
        return desc
      end
    end
    nil
  end

  # The decorator lines stacked directly above the `def` at `def_idx`,
  # bottom up, ending at a route decorator: Flask registers what the route
  # decorator receives, so the ones above it never wrap the view.
  private def decorators_above(lines : Array(String), def_idx : Int32) : Array(String)
    found = [] of String
    depth = 0
    idx = def_idx - 1
    while idx >= 0
      line = Analyzer::Python::Helper.strip_python_comment(lines[idx]).strip
      idx -= 1
      next if line.empty? && depth > 0
      # Walking up, a multi-line decorator's closing bracket comes first.
      depth += line.count(")]}") - line.count("([{")
      next if depth > 0
      break if !line.starts_with?('@') || line.matches?(ROUTE_DECORATOR)
      found << line
    end
    found
  end

  # The guard a decorator line names, judged by the decorator's definition
  # when the scan has it, by its name only when it does not (a library
  # decorator such as flask-login's `login_required`).
  private def decorator_guard(line : String, file : String) : String?
    name = line.match(DECORATOR_NAME).try(&.[1]) || return
    target = resolve(file, name) { |path, def_name| python_defs(path).has_key?(def_name) }
    return decorator_description(line) unless target
    verdict = @verdicts[target]?
    verdict = @verdicts[target] = guard_definition?(target[0], target[1], 0) if verdict.nil?
    name if verdict
  end

  # Whether `def name` in `file` turns an unauthenticated caller away, in
  # its own body or in a function it calls, up to two calls deep: Dify's
  # `validate_jwt_token` rejects inside `decode_jwt_token`,
  # `console_account_admission` returns `login_required(...)` of the view,
  # and `_api_prerequisite` stacks `@login_required` on its inner wrapper.
  private def guard_definition?(file : String, name : String, hops : Int32) : Bool
    body = python_defs(file)[name]
    return true if body.matches?(UNAUTHENTICATED) ||
                   (body.matches?(REQUEST_CREDENTIAL) && body.matches?(REJECTION)) ||
                   (body.matches?(CALLER_IDENTITY) && body.matches?(FORBIDDEN))
    return false if hops >= 2
    body.scan(CALLEE).map { |m| m[1]? || m[2] }.uniq!.any? do |callee|
      next false if callee == name
      target = resolve(file, callee) { |path, def_name| python_defs(path).has_key?(def_name) }
      !!target && guard_definition?(target[0], target[1], hops + 1)
    end
  end

  # `name` (`x` or `mod.x`) as used in `file`: `file` itself when it
  # declares it, else the module it is imported from; nil when the scan
  # holds no declaration.
  private def resolve(file : String, name : String, & : String, String -> Bool) : Tuple(String, String)?
    mod, _, leaf = name.rpartition('.')
    imports = python_imported_symbols(file)
    target = if mod.empty?
               (yield file, leaf) ? {file, leaf} : imports[leaf]?
             elsif (module_file = imports[mod]?) && module_file[1].empty?
               {module_file[0], leaf}
             end
    target if target && !target[1].empty? && yield target[0], target[1]
  end

  # Top-level `def` bodies of `path` by name, comments and docstrings
  # dropped. `@overload` stubs share their implementation's name, so a
  # name's bodies are joined.
  private def python_defs(path : String) : Hash(String, String)
    @python_defs[path] ||= begin
      bodies = Hash(String, String::Builder).new
      name = nil
      (read_file_lines(path) || [] of String).each do |line|
        if m = line.match(TOP_LEVEL_DEF)
          name = m[1]
        elsif !line.blank? && !line[0].ascii_whitespace? && !line[0].in?(')', ']')
          name = nil
        end
        if current = name
          (bodies[current] ||= String::Builder.new) << Analyzer::Python::Helper.strip_python_comment(line) << '\n'
        end
      end
      bodies.transform_values(&.to_s.gsub(DOCSTRING, ""))
    end
  end

  # `method_decorators` / `decorators` of class `name` in `file`, or of the
  # nearest base class declaring them, with the file that declares the
  # list (where its names resolve). Every method of a class asks, so the
  # answer is kept per class.
  private def class_decorators(file : String, name : String, depth : Int32 = 0) : Tuple(String, Array(String))?
    key = {file, name}
    return @class_decorators[key] if @class_decorators.has_key?(key)
    @class_decorators[key] = depth > 5 ? nil : scan_class_decorators(file, name, depth)
  end

  private def scan_class_decorators(file : String, name : String, depth : Int32) : Tuple(String, Array(String))?
    lines = read_file_lines(file) || return
    start = lines.index { |line| line.match(CLASS_DEF).try(&.[1]) == name } || return
    idx = start + 1
    while idx < lines.size && (lines[idx].blank? || lines[idx][0].ascii_whitespace?)
      if m = lines[idx].match(CLASS_DECORATORS)
        text = m[1]
        while text.count("([{") > text.count(")]}") && (idx += 1) < lines.size
          text += lines[idx]
        end
        names = text.gsub(PY_STRING, "").scan(/(?:^\s*[\[({]?|[\[,{:])\s*([A-Za-z_][\w.]*)/).map(&.[1])
        return {file, names}
      end
      idx += 1
    end
    lines[start].match(CLASS_DEF).try(&.[2]?).to_s.split(',').each do |base|
      base = base.strip
      next if base.empty? || base.includes?('=')
      target = resolve(file, base) do |path, class_name|
        !!read_file_lines(path).try(&.any? { |line| line.match(CLASS_DEF).try(&.[1]) == class_name })
      end
      if target && (found = class_decorators(target[0], target[1], depth + 1))
        return found
      end
    end
    nil
  end

  private def decorator_description(line : String) : String?
    DECORATOR_PATTERNS.each do |pattern, desc|
      return desc if line.matches?(pattern)
    end
    nil
  end
end
