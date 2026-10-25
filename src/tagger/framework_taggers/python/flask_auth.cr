require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../analyzer/analyzers/python/python_helper"
require "./python_guard_definitions"

@[Noir::TaggerFor(key: "flask_auth", name: "Flask Auth Tagger", desc: "Identifies Flask authentication patterns (flask-login, flask-jwt, flask-httpauth)", order: 90)]
class FlaskAuthTagger < FrameworkTagger
  include PythonGuardDefinitions

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

  ROUTE_DECORATOR = /^@[\w.]+\.(?:route|get|post|put|patch|delete)\s*\(/
  CLASS_DEF       = /^class\s+(\w+)\s*(?:\((.*)\))?\s*:/
  # flask-restx `Resource.method_decorators`, Flask `View.decorators`.
  CLASS_DECORATORS = /^\s+(?:method_decorators|decorators)\s*(?::[^=]+)?=([^=].*)/
  PY_STRING        = /"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/

  # What an authorization check decides on, as opposed to a feature flag or
  # a quota: a permission-check call, or a role / permission / ownership
  # field tested in a condition. Only the condition counts for a field:
  # Dify's token decorators query `TenantAccountJoin.role == "owner"` to
  # find the tenant owner, which checks nothing about the caller.
  AUTHZ_CALL      = /\b(?:has_\w*perm\w*|check_access|CheckAccess)\b/
  AUTHZ_CONDITION = /(?m)^[ \t]*(?:if|elif|while|assert|case)\b.*(?:\.(?:roles?|permissions?|is_superuser|is_staff|is_admin\w*|is_owner\w*|owner_id)\b|\bowner(?:_id)?\s*[!=]=)/

  def self.target_techs : Array(String)
    ["python_flask"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @class_decorators = Hash(Tuple(String, String), Tuple(String, Array(String))?).new
    @authz_params = Hash(Tuple(String, String, Int32), Array(String)?).new
  end

  private def check_endpoint(endpoint : Endpoint)
    auth, authz = handler_guards(endpoint)
    auth ||= code_path_guard(endpoint)
    endpoint.add_tag(Tag.new("auth", "Protected by #{auth}", "flask_auth")) if auth
    endpoint.add_tag(Tag.new("authz", "Protected by #{authz}", "flask_auth")) if authz
  end

  # The auth decorator at the route's declaration line, for a route whose
  # handler the analyzer did not resolve.
  private def code_path_guard(endpoint : Endpoint) : String?
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
            return desc
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
          return desc
        end

        idx -= 1
      end
    end
    nil
  end

  # The guard on the handler the analyzer resolved, outermost first: for a
  # flask-restx Resource or Flask MethodView method, the class's
  # `method_decorators` / `decorators` (inherited from a base class when the
  # class does not set them, as Dify's `WebApiResource` subclasses do), then
  # the decorators stacked on the `def`, top down. Returns the first
  # authentication guard and the first authorization guard among them.
  private def handler_guards(endpoint : Endpoint) : Tuple(String?, String?)
    none = {nil, nil}
    handler = endpoint.handler || return none
    file = handler.path || return none
    def_idx = (handler.line || return none) - 1
    lines = read_file_lines(file) || return none
    return none unless 0 <= def_idx < lines.size
    decorators = [] of Tuple(String, String)
    class_name = handler.name.rpartition('.')[0]
    if !class_name.empty? && (found = class_decorators(file, class_name))
      found[1].each { |name| decorators << {"@#{name}", found[0]} }
    end
    decorators_above(lines, def_idx).reverse_each { |line| decorators << {line, file} }
    auth = authz = nil
    decorators.each do |line, declaring_file|
      auth ||= decorator_guard(line, declaring_file)
      authz ||= decorator_authz(line, declaring_file)
    end
    {auth, authz}
  end

  # The decorator lines stacked directly above the `def` at `def_idx`,
  # bottom up, ending at a route decorator: Flask registers what the route
  # decorator receives, so the ones above it never wrap the view. A
  # multi-line decorator comes back as one line, arguments included.
  private def decorators_above(lines : Array(String), def_idx : Int32) : Array(String)
    found = [] of String
    args = [] of String
    depth = 0
    idx = def_idx - 1
    while idx >= 0
      line = Analyzer::Python::Helper.strip_python_comment(lines[idx]).strip
      idx -= 1
      next if line.empty? && depth > 0
      # Walking up, a multi-line decorator's closing bracket comes first.
      depth += line.count(")]}") - line.count("([{")
      if depth > 0
        args.unshift(line)
        next
      end
      break if !line.starts_with?('@') || line.matches?(ROUTE_DECORATOR)
      found << args.unshift(line).join(' ')
      args.clear
    end
    found
  end

  # The authorization a decorator line applies, judged by its definition
  # (`authz_params`); a decorator that authorizes only when configured to
  # counts only where this line passes one of those parameters a value.
  private def decorator_authz(line : String, file : String) : String?
    match = line.match(DECORATOR_NAME) || return
    target = resolve_def(file, match[1]) || return
    # Not where the caller's own branch reaches the view unchecked
    # (`if in_window() or current_user.is_admin:`). A setting that skips
    # the check (`if not RBAC_ENABLED`) still leaves one where it applies.
    return if view_access(target[0], target[1]).caller?
    gates = authz_params(target[0], target[1], 0) || return
    args = match.post_match
    match[1] if gates.empty? || gates.any? { |gate| args.matches?(/\b#{gate}\s*=\s*(?!None\b|False\b|\(\s*\)|\[\s*\]|\{\s*\})\S/) }
  end

  # Whether `def name` in `file` denies with 403 on a role, permission or
  # ownership read, in its own body or through a function or decorator it
  # applies, up to two calls deep. Nil when it does not; otherwise the
  # parameters of `name` that gate every such path, empty when one path is
  # ungated. Dify's `console_account_admission` checks roles only `if
  # allowed_roles is not None` and RBAC only `if rbac_checks is not None`,
  # so `@console_account_admission()` alone authorizes nothing.
  private def authz_params(file : String, name : String, hops : Int32) : Array(String)?
    key = {file, name, hops}
    return @authz_params[key] if @authz_params.has_key?(key)
    @authz_params[key] = scan_authz_params(file, name, hops)
  end

  private def scan_authz_params(file : String, name : String, hops : Int32) : Array(String)?
    body = python_defs(file)[name]
    own = body.matches?(FORBIDDEN) && (body.matches?(AUTHZ_CALL) || body.matches?(AUTHZ_CONDITION))
    return unless own || hops < 2
    lines = body.lines
    sig_end, params = signature(lines)
    gates = [] of String
    found = false
    lines.each_with_index do |line, idx|
      next if idx <= sig_end
      site = (own && line.matches?(FORBIDDEN)) || (hops < 2 && line.scan(CALLEE).any? do |m|
        callee = m[1]? || m[2]
        callee != name && (target = resolve_def(file, callee)) && authz_params(target[0], target[1], hops + 1).try(&.empty?)
      end)
      next unless site
      found = true
      governing = governing_text(lines, idx, sig_end)
      gate = params.select { |param| governing.matches?(/\b#{param}\b/) }
      return [] of String if gate.empty?
      gates.concat(gate)
    end
    gates.uniq if found
  end

  # The conditions line `idx` of a body runs under: the block headers
  # enclosing it up to the signature ending at `sig_end`, and the line
  # itself when it is a one-line `if`. Not the line's own arguments:
  # `enforce_rbac_checks(checks=checks)` passes a parameter on, it does
  # not make the check conditional on it.
  private def governing_text(lines : Array(String), idx : Int32, sig_end : Int32) : String
    String.build do |io|
      io << lines[idx] if lines[idx].matches?(/^\s*(?:if|elif)\b/)
      threshold = lines[idx].size - lines[idx].lstrip.size
      j = idx - 1
      while j > sig_end && threshold > 0
        line = lines[j]
        indent = line.size - line.lstrip.size
        if !line.blank? && indent < threshold
          io << '\n' << line
          threshold = indent
        end
        j -= 1
      end
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
