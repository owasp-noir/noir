require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../analyzer/analyzers/python/python_helper"
require "./python_guard_definitions"
require "./python_auth_access"
require "../../../utils/python_mro"

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
    # Flask-AppBuilder's permission checks: each refuses a caller without
    # the view's permission, unless the Public role (AUTH_ROLE_PUBLIC) holds it.
    {/\@protect\s*\(/, "flask-appbuilder protect (a setting can make it public)"},
    {/\@has_access\b/, "flask-appbuilder has_access (a setting can make it public)"},
    {/\@has_access_api\b/, "flask-appbuilder has_access_api (a setting can make it public)"},
    # APIFairy's `@authenticate(auth)` applies `auth.login_required`, which
    # answers 401 without credentials unless it is `optional=True`.
    {/\@authenticate\s*\((?![^)]*\boptional\s*=\s*True\b)/, "apifairy authenticate"},
    {/\@requires_auth/, "requires_auth"},
    {/\@authenticated/, "authenticated"},
  ]

  APIFAIRY_IMPORT = /^\s*from\s+apifairy\s+import\s*(?:\([^)]*|[^\n]*)\bauthenticate\b/m
  ROUTE_DECORATOR = /^@([\w.]+)\.(?:route|get|post|put|patch|delete)\s*\(/
  CLASS_DEF       = /^class\s+(\w+)\s*(?:\((.*)\))?\s*:/
  # flask-restx `Resource.method_decorators`, Flask `View.decorators`.
  CLASS_DECORATORS = /^\s+(method_decorators|decorators)\s*(?::[^=]+)?=([^=].*)/
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

  # A decorator as a class list names it (`login_required`, judged as
  # `@login_required`) and as written there (`jwt_required(optional=True)`),
  # with the file its name resolves in.
  private record Listed, file : String, line : String, source : String

  # One layer that applies to the view: the text that names the tag (nil
  # for a layer the tagger does not judge a guard but that may refuse) and
  # what it requires.
  private record Guard, description : String?, requires : Array(Access::Clause)

  SETTING_OPENS = "(a setting can make it public)"

  def initialize(options : Hash(String, YAML::Any))
    super
    @class_decorators = Hash(Tuple(String, String), Array(Listed)?).new
    @authz_params = Hash(Tuple(String, String, Int32), Array(String)?).new
  end

  # Every layer applies: the view's decorators (or, for a handler the
  # analyzer did not resolve, the route's), the handler's own refusal, and
  # the router's `before_request` hooks. The first judged guard names the
  # tag, as it did before the requirement was read.
  private def check_endpoint(endpoint : Endpoint)
    method = endpoint.method.upcase
    guards, authz = handler_guards(endpoint, method)
    guards.concat(code_path_guards(endpoint, method)) if guards.none?(&.description)
    body_guard(endpoint, method).try { |found| guards << found }
    guards.concat(before_request_guards(endpoint, method))
    if first = guards.find(&.description)
      guards.concat(api_decorator_guards(endpoint))
      endpoint.add_tag(Tag.new("auth", "Protected by #{first.description}", "flask_auth", requires: guards.flat_map(&.requires).uniq!))
    end
    endpoint.add_tag(Tag.new("authz", "Protected by #{authz}", "flask_auth")) if authz
  end

  # The handler's own refusal of a caller who is not logged in.
  private def body_guard(endpoint : Endpoint, method : String) : Guard?
    handler = endpoint.handler || return
    file = handler.path || return
    lines = read_file_lines(file) || return
    def_idx = (handler.line || return) - 1
    description = "handler refusing a caller who is not logged in"
    cnf = anonymous_refusal(file, lines, def_idx, method, description) || return
    Guard.new(description, Access.clauses(cnf, description))
  end

  # flask-restx `Api(..., decorators=[...])` / `Namespace(..., decorators=
  # [...])` and flask-restful `Api(..., decorators=[...])` wrap every
  # resource they register. Which one serves this view is not followed, so
  # one in the view's files is a check noir did not read.
  API_DECORATORS = /\b(?:Api|Namespace)\s*\((?:[^()]|\([^()]*\))*?\bdecorators\s*=/

  private def api_decorator_guards(endpoint : Endpoint) : Array(Guard)
    files = ([endpoint.handler.try(&.path)] + endpoint.details.code_paths.map(&.path)).compact.uniq!
    files.compact_map do |file|
      next unless read_file(file).try(&.matches?(API_DECORATORS))
      fragment = "decorators= on an Api or Namespace in #{File.basename(file)}"
      Guard.new(nil, Access.clauses(PythonAuthAccess.unresolved(fragment), fragment))
    end
  end

  # A `@<router>.before_request` hook in the route's file runs before every
  # view of that app or blueprint, and what it returns answers the request
  # in the view's place. The router is guarded when the hook is wrapped by
  # an auth decorator (`@bp.before_request` over `@login_required`), or when
  # its body refuses a caller who is not logged in the way `body_guard`
  # reads a handler: a hook that returns early for some requests guards
  # nothing.
  # ponytail: same file and same router name only; a hook on a blueprint
  # the route file imports, or on the app a blueprint is registered on, is
  # not followed.
  # Every hook of the router runs, so each one contributes; one the tagger
  # does not judge a guard still adds what it may refuse as unresolved.
  private def before_request_guards(endpoint : Endpoint, method : String) : Array(Guard)
    guards = [] of Guard
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path) || next
      route_line = lines[(path_info.line || next) - 1]? || next
      router = route_line.strip.match(ROUTE_DECORATOR).try(&.[1]) || next
      hook = "@#{router}.before_request"
      lines.each_with_index do |text, idx|
        next unless text.strip == hook
        def_idx = idx + 1
        while def_idx < lines.size && lines[def_idx].lstrip.starts_with?('@')
          entry = Listed.new(path_info.path, lines[def_idx].strip, lines[def_idx].strip)
          if desc = decorator_guard(entry.line, entry.file)
            guards << guard("#{desc} on #{router}.before_request", decorator_access(entry, desc, method, nil), entry.source)
          elsif refusal = unjudged_refusal(entry)
            guards << refusal
          end
          def_idx += 1
        end
        description = "#{router}.before_request refusing a caller who is not logged in"
        if cnf = anonymous_refusal(path_info.path, lines, def_idx, method, description)
          guards << guard(description, cnf, description)
        elsif function_body(lines, def_idx).any? { |(_, code)| refusal_statement?(code) }
          fragment = "#{router}.before_request #{lines[def_idx]?.to_s.strip}"
          guards << Guard.new(nil, Access.clauses(PythonAuthAccess.unresolved(fragment), fragment))
        end
      end
    end
    guards
  end

  # What passing the function at `def_idx` takes when it turns away a
  # caller who is not logged in before any path that answers `method`:
  # Superset's `welcome` opens with `if not g.user or not get_user_id():
  # return redirect_to_login()`.
  # The `if` must hold only for an unidentified caller (`implies_identity?`
  # on its false branch) and its block must refuse: a login redirect, a 401,
  # or a 403. Top-level statements are read in order, and the walk stops at
  # the first one that may answer first: a `return`, or a block holding a
  # `return` that is not a refusal (`if request.method == "GET": return
  # page()` leaves GET open, but not POST). A test on `request.method` is
  # decided for `method`. `if not is_feature_enabled(...):
  # abort(404)` reads no caller and answers nobody, so the walk goes on.
  # Nil when it does not refuse. Signed in when the test is a plain sign-in
  # check and the function refuses nowhere else; otherwise signed in plus
  # `description` unresolved, for what else the test or those refusals decide.
  private def anonymous_refusal(file : String, lines : Array(String), def_idx : Int32, method : String, description : String) : Access::CNF?
    body = function_body(lines, def_idx)
    level = body.first?.try(&.[0]) || return
    body.each_with_index do |(indent, code), k|
      next unless indent == level
      return if code.starts_with?("return")
      block = body[(k + 1)..].take_while { |entry| entry[0] > level }.map(&.[1])
      if if_match = code.match(/\A(?:if|elif)\s+(.+?):\s*(.*)\z/)
        inline = if_match[2]
        block.unshift(inline) unless inline.empty?
        cond = method_condition(if_match[1], method)
        next if cond == false # never taken for this method
        if cond.is_a?(String) && !block.empty? && block.first.matches?(BODY_REFUSAL) &&
           implies_identity?(cond, false, file, Hash(String, String).new, [] of String)
          plain = cond.strip.matches?(SIGN_IN_TEST) && body.count { |(_, statement)| refusal_statement?(statement) } == 1
          return plain ? PythonAuthAccess.signed_in : DjangoAccess.unread(description)
        end
        return if cond == true && block.any?(&.starts_with?("return"))
      end
      # Any other way this statement may answer first.
      return if block.any? { |statement| statement.starts_with?("return") && !statement.matches?(BODY_REFUSAL) }
    end
    nil
  end

  # A test that holds exactly for a caller who is not signed in.
  SIGN_IN_TEST = /\A(?:not\s+(?:flask_login\.)?current_user\.is_authenticated|(?:flask_login\.)?current_user\.is_anonymous|not\s+g\.user|g\.user\s+is\s+None)\z/

  # The statements of the function whose `def` is at `def_idx`, past its
  # signature (which may wrap), with their indents, comments cut.
  private def function_body(lines : Array(String), def_idx : Int32) : Array({Int32, String})
    body = [] of {Int32, String}
    return body unless 0 <= def_idx < lines.size
    def_indent = lines[def_idx].size - lines[def_idx].lstrip.size
    idx = def_idx + 1
    while idx < lines.size && !Analyzer::Python::Helper.strip_python_comment(lines[idx - 1]).rstrip.ends_with?(':')
      idx += 1
    end
    lines[idx..].each do |raw|
      line = Analyzer::Python::Helper.strip_python_comment(raw).rstrip
      next if line.blank?
      indent = line.size - line.lstrip.size
      break if indent <= def_indent
      body << {indent, line.strip}
    end
    body
  end

  # Whether a statement (or the one a one-line block header holds) turns
  # the request away.
  private def refusal_statement?(code : String) : Bool
    statement = code.sub(/\A(?:if|elif|else|except|try|with|for|while)\b[^:]*:\s*/, "")
    statement.matches?(/\A(?:return|raise|abort)\b/) &&
      (statement.matches?(BODY_REFUSAL) || statement.matches?(REJECTION) || statement.matches?(FORBIDDEN))
  end

  BODY_REFUSAL = /\A(?:return|raise|abort)\b.*(?:#{LOGIN_REDIRECT.source}|\bredirect_to_(?:log_?in|sign_?in)\b|\b40[13]\b|Unauthori[sz]ed|Forbidden|\.response_40[13]\s*\()/i
  METHOD_TEST  = /\Arequest\.method\s*(==|!=|in|not\s+in)\s*(.+)\z/
  METHOD_VERBS = /['"]([A-Za-z]+)['"]/

  # `cond` for an endpoint answering `method`: `true` / `false` when it is
  # only a `request.method` test, otherwise the condition left once its
  # `and`-joined method tests are decided (`false` when one fails).
  private def method_condition(cond : String, method : String) : String | Bool
    parts = cond.split(/\s+and\s+/)
    kept = [] of String
    parts.each do |part|
      if (test = part.strip.match(METHOD_TEST)) && !cond.matches?(/\sor\s/)
        verbs = test[2].scan(METHOD_VERBS).map(&.[1].upcase)
        holds = verbs.includes?(method)
        holds = !holds if test[1] == "!=" || test[1].starts_with?("not")
        return false unless holds
      else
        kept << part
      end
    end
    kept.empty? ? true : kept.join(" and ")
  end

  # The auth decorator at the route's declaration line, for a route whose
  # handler the analyzer did not resolve.
  private def code_path_guards(endpoint : Endpoint, method : String) : Array(Guard)
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
        # A decorator's wrapped arguments (`optional=True` on its own line) belong to it.
        decorators = [] of String
        annotation_lines_below(lines, route_idx, "@").each do |current|
          if current.starts_with?('@') || decorators.empty?
            decorators << current
          else
            decorators[-1] += " #{current}"
          end
        end
        guards = decorators.compact_map { |current| judged_guard(Listed.new(path_info.path, current, current), method, nil) }
        return guards if guards.any?(&.description)
        next
      end

      # Otherwise the line is the view itself: walk back over its decorators.
      # 8-line window: Flask decorators stack above def, typically 1-5 decorators
      guards = [] of Guard
      idx = line_num - 2 # 0-indexed, one line before
      while idx >= 0 && idx >= line_num - 10
        current = lines[idx].strip
        break if current.empty? && idx < line_num - 2

        if current.starts_with?('@') && (found = judged_guard(Listed.new(path_info.path, current, current), method, nil))
          guards << found
        end

        idx -= 1
      end
      return guards if guards.any?(&.description)
    end
    [] of Guard
  end

  # The guard on the handler the analyzer resolved, outermost first: for a
  # flask-restx Resource or Flask MethodView method, the class's
  # `method_decorators` / `decorators` (inherited from a base class when the
  # class does not set them, as Dify's `WebApiResource` subclasses do), then
  # the decorators stacked on the `def`, top down. Returns the first
  # authentication guard and the first authorization guard among them; every
  # guard in the stack adds what it requires.
  private def handler_guards(endpoint : Endpoint, method : String) : Tuple(Array(Guard), String?)
    none = {[] of Guard, nil}
    handler = endpoint.handler || return none
    file = handler.path || return none
    def_idx = (handler.line || return none) - 1
    lines = read_file_lines(file) || return none
    return none unless 0 <= def_idx < lines.size
    decorators = [] of Listed
    class_file, class_name = registered_class(endpoint) || {file, handler.name.rpartition('.')[0]}
    if !class_name.empty? && (found = class_decorators(class_file, class_name))
      decorators.concat(found)
    end
    stack = decorators_above(lines, def_idx)
    stack.reverse_each { |line| decorators << Listed.new(file, line, line) }
    view = class_name.empty? ? nil : fab_permission(stack, handler.name.rpartition('.')[2], class_name)
    authz = nil
    guards = decorators.compact_map do |entry|
      authz ||= decorator_authz(entry.line, entry.file)
      judged_guard(entry, method, view)
    end
    {guards, authz}
  end

  # The permission a Flask-AppBuilder decorator on `def_name` of `view`
  # checks: `@permission_name("x")` in the stack names it, else the method.
  private def fab_permission(stack : Array(String), def_name : String, view : String) : String
    named = stack.compact_map(&.match(/\A@permission_name\s*\((.*)\)\s*\z/)).first?
    permission = named ? (PythonAuthAccess.literal(named[1]) || "<#{named[1].strip}>") : def_name
    PythonAuthAccess.fab_permission(permission, view)
  end

  private def guard(description : String?, cnf : Access::CNF, source : String) : Guard
    Guard.new(description, Access.clauses(cnf, source.lchop('@')))
  end

  # The guard a decorator applies, judged as before; a project decorator
  # not judged one whose definition still refuses adds an unread check.
  private def judged_guard(entry : Listed, method : String, view : String?) : Guard?
    if description = decorator_guard(entry.line, entry.file)
      return guard(description, decorator_access(entry, description, method, view), entry.source)
    end
    unjudged_refusal(entry)
  end

  private def unjudged_refusal(entry : Listed) : Guard?
    name = entry.line.match(DECORATOR_NAME).try(&.[1]) || return
    file, def_name = resolve_def(entry.file, name) || return
    body = without_view_error_handlers(python_defs(file)[def_name])
    return unless body.lines.any? { |line| refusal_statement?(line.strip) }
    guard(nil, PythonAuthAccess.unresolved(entry.source.lchop('@')), entry.source)
  end

  # What a decorator judged a guard requires. A project decorator is read
  # no further than the verdict that it refuses an anonymous caller: its
  # arguments stay text. A library one is read only when this file binds
  # its name to the library. `view` names the Flask-AppBuilder permission.
  private def decorator_access(entry : Listed, description : String, method : String, view : String?) : Access::CNF
    name, args, source = DjangoAccess.call(entry.source) || return DjangoAccess.unread(description)
    if resolve_def(entry.file, name)
      cnf = DjangoAccess.unread(source)
      return description.ends_with?(SETTING_OPENS) ? DjangoAccess.liftable(cnf, description) : cnf
    end
    return PythonAuthAccess.fab(view || source, description) if description.starts_with?("flask-appbuilder")
    if description.starts_with?("apifairy")
      auth = args.try { |text| Noir::TopLevelSplit.split(text, ',', DjangoAccess::ARGS).first? } || ""
      return httpauth_object?(entry.file, auth) ? PythonAuthAccess.httpauth(args, source, true, method) : DjangoAccess.unread(description)
    end
    receiver, _, leaf = name.rpartition('.')
    if leaf == "login_required" && !receiver.empty?
      return httpauth_object?(entry.file, receiver) ? PythonAuthAccess.httpauth(args, source, true, method) : DjangoAccess.unread(description)
    end
    if qualified = from_imports(entry.file)[name]?
      login_disabled = qualified.matches?(/\Aflask_(?:login|security)\b.*\.login_required\z/) && login_disabled?
      PythonAuthAccess.library_decorator(qualified, args, source, method, login_disabled).try { |cnf| return cnf }
    end
    DjangoAccess.unread(description)
  end

  @from_imports = Hash(String, Hash(String, String)).new

  private def from_imports(path : String) : Hash(String, String)
    @from_imports[path] ||= PythonAuthAccess.from_imports(read_file(path) || "")
  end

  HTTPAUTH_CLASSES = %w[HTTPBasicAuth HTTPTokenAuth HTTPDigestAuth MultiAuth]

  # Whether `name` in `file` is a Flask-HTTPAuth object: assigned from one
  # of its classes in the module that declares it.
  private def httpauth_object?(file : String, name : String) : Bool
    return false if name.empty?
    !!resolve(file, name) do |path, instance|
      read_file(path).try(&.scan(ALLOWS_INSTANCE).any? do |m|
        next false unless m[1] == instance
        mod, _, ctor = m[2].rpartition('.')
        HTTPAUTH_CLASSES.includes?(ctor) && (mod.empty? ? from_imports(path)[ctor]? == "flask_httpauth.#{ctor}" : mod == "flask_httpauth")
      end) || false
    end
  end

  @login_disabled : Bool? = nil

  # Whether any source of the scan mentions flask_login's `LOGIN_DISABLED`.
  private def login_disabled? : Bool
    if (known = @login_disabled).nil?
      known = @login_disabled = collect_files_by_extension(".py").any? { |file| !!CodeLocator.instance.read_source(file).try(&.includes?("LOGIN_DISABLED")) }
    end
    known
  end

  # The class view registered for the route when its handler is a method
  # it inherits: the analyzer adds that class's `class` line as a code
  # path. Its MRO, not the defining class's, decides the class decorators.
  private def registered_class(endpoint : Endpoint) : Tuple(String, String)?
    endpoint.details.code_paths.each do |path_info|
      line = path_info.line || next
      text = read_file_lines(path_info.path).try(&.[line - 1]?) || next
      if name = text.lstrip.match(CLASS_DEF).try(&.[1])
        return {path_info.path, name}
      end
    end
    nil
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
      # A comment line inside the stack (`# pylint: disable=...` above the
      # `def`) is no end of it.
      next if line.empty?
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
    return flask_allows_desc(line) if flask_allows_requires?(match[1], line, file)
    target = resolve_def(file, match[1]) || return
    # Not where the caller's own branch reaches the view unchecked
    # (`if in_window() or current_user.is_admin:`). A setting that skips
    # the check (`if not RBAC_ENABLED`) still leaves one where it applies.
    return if view_access(target[0], target[1]).caller?
    gates = authz_params(target[0], target[1], 0) || return
    args = match.post_match
    match[1] if gates.empty? || gates.any? { |gate| args.matches?(/\b#{gate}\s*=\s*(?!None\b|False\b|\(\s*\)|\[\s*\]|\{\s*\})\S/) }
  end

  # flask-allows: `@allows.requires(IsAdmin, ...)` on an `allows =
  # Allows(...)` instance, `@fa.requires(...)` on the module, or a bare
  # `@requires(...)` bound to flask_allows' (or its flask_allows2 fork,
  # FlaskBB's) by this file's imports, aliases included, refuses (403, or
  # the `on_fail` handler) a caller whose identity fails the
  # requirements: an authorization check. A project's own `requires`
  # decides nothing here, nor do requirements that only negate
  # (`requires(Not(...))`); `Not` negates only its own argument.
  ALLOWS_INSTANCE    = /^([A-Za-z_]\w*)[ \t]*(?::[^=\n]+)?=[ \t]*([A-Za-z_][\w.]*)[ \t]*\(/m
  ALLOWS_MODULE      = /\Aflask_allows2?(?:\.|\z)/
  IMPORT_PARENS      = /(\bimport[ \t]*)\(([^)]*)\)/
  FROM_IMPORT_LINE   = /^[ \t]*from[ \t]+([\w.]+)[ \t]+import[ \t]+([^\n]+)/m
  PLAIN_IMPORT_LINE  = /^[ \t]*import[ \t]+([^\n]+)/m
  TOP_LEVEL_REQUIRES = /^(?:async[ \t]+)?def[ \t]+requires\b/m

  @allows_bindings = Hash(String, Hash(String, String)).new

  # What each name `path` binds means in flask_allows: "requires",
  # "Allows" or "module"; "" for a name a later import or def took over.
  private def allows_bindings(path : String) : Hash(String, String)
    @allows_bindings[path] ||= begin
      bindings = Hash(String, String).new
      source = (read_file(path) || "").gsub(IMPORT_PARENS) { "#{$1}#{$2.gsub(/#[^\n]*/, "").gsub(/\s+/, " ")}" }
      if source.includes?("flask_allows")
        statements = [] of Tuple(Int32, String, String?)
        source.scan(FROM_IMPORT_LINE) { |m| statements << {m.begin(0), m[2], m[1]} }
        source.scan(PLAIN_IMPORT_LINE) { |m| statements << {m.begin(0), m[1], nil} }
        statements.sort_by!(&.[0]).each do |_, items, from|
          items.sub(/#.*/, "").split(',').each do |item|
            name, _, bound = item.strip.partition(/\s+as\s+/)
            bound = name if bound.empty?
            next if name.empty?
            if from
              bindings[bound] = from.matches?(ALLOWS_MODULE) && name.in?("requires", "Allows") ? name : ""
            elsif name.matches?(ALLOWS_MODULE)
              bindings[bound] = "module"
            end
          end
        end
        bindings["requires"] = "" if source.matches?(TOP_LEVEL_REQUIRES)
      end
      bindings
    end
  end

  private def flask_allows_requires?(name : String, line : String, file : String) : Bool
    receiver, _, leaf = name.rpartition('.')
    if receiver.empty?
      return false unless allows_bindings(file)[name]? == "requires"
    else
      return false unless leaf == "requires"
    end
    return false if only_negations?(line)
    return true if receiver.empty? || allows_bindings(file)[receiver]? == "module"
    !!resolve(file, receiver) do |path, instance|
      bindings = allows_bindings(path)
      read_file(path).try(&.scan(ALLOWS_INSTANCE).any? do |m|
        next false unless m[1] == instance
        mod, _, ctor = m[2].rpartition('.')
        mod.empty? ? bindings[ctor]? == "Allows" : ctor == "Allows" && (bindings[mod]? == "module" || mod.matches?(ALLOWS_MODULE))
      end) || false
    end
  end

  # `requires(Not(is_banned))` / `requires(~x)`: every requirement only
  # negates, so it never asks who the caller is. `requires(Not(x), is_admin)`
  # still demands is_admin.
  private def only_negations?(line : String) : Bool
    args = line.partition(/\brequires\s*\(/)[2]
    return false if args.empty?
    depth = 1
    stop = args.size
    args.each_char_with_index do |char, i|
      depth += 1 if char.in?('(', '[', '{')
      depth -= 1 if char.in?(')', ']', '}')
      if depth == 0
        stop = i
        break
      end
    end
    requirements = Noir::TopLevelSplit.split(args[0, stop], ',', Noir::TopLevelSplit::Rules.new)
      .map(&.strip).reject { |part| part.empty? || part.matches?(/\A\w+\s*=(?!=)/) }
    !requirements.empty? && requirements.all?(&.matches?(/\A(?:Not\s*\(|~)/))
  end

  # A requirement built from the request (`ForRequest(can_access_forum,
  # request_forum)`, `can_post_reply(topic)`) is decided by the requested
  # resource's settings, which can let a guest through; a fixed one
  # (`IsAdmin`, `IsAtLeast(GroupRole.MODERATOR)`) is not.
  # ponytail: a lowercase call or `ForRequest(` marks the per-request kind;
  # evaluate the requirement definitions if a project mixes the styles.
  private def flask_allows_desc(line : String) : String
    args = line.partition('(')[2]
    requirements = args.sub(/,?\s*\b(?:on_fail|throws|identity)\s*=[\s\S]*\z/, "")
    if requirements.matches?(/\bForRequest\s*\(|(?<![\w.])[a-z_][\w]*\s*\(/)
      "flask-allows requires (a per-request requirement: the resource's settings can admit a guest)"
    else
      "flask-allows requires"
    end
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

  # Flask `View.decorators` (wrapping the view `as_view` builds) and
  # flask-restful / flask-restx `Resource.method_decorators` (wrapping the
  # verb method) of class `name` in `file`, each entry with the file that
  # declares it (where its name resolves). Each attribute is looked up the
  # way Python does, along the class's MRO, so a subclass's own list (even
  # `decorators = []`) wins over a base's, and a module-level
  # `View.decorators = [...]` / `+= [...]` after the class body counts. A
  # list built from another class's (`BaseResource.decorators + [...]`)
  # holds that class's entries. Nil when neither attribute is set.
  private def class_decorators(file : String, name : String) : Array(Listed)?
    key = {file, name}
    return @class_decorators[key] if @class_decorators.has_key?(key)
    @class_decorators[key] = nil # a self-referencing list ends here
    found = nil
    CLASS_DECORATOR_ATTRS.each do |attr|
      if entries = class_attr(file, name, attr, 0)
        (found ||= [] of Listed).concat(entries)
      end
    end
    @class_decorators[key] = found
  end

  CLASS_DECORATOR_ATTRS = %w[decorators method_decorators]

  private def class_attr(file : String, name : String, attr : String, depth : Int32) : Array(Listed)?
    return if depth > 5
    mro = Noir::PythonMRO.linearize({file, name}) { |node| class_bases(node[0], node[1]) }
    mro_attr(mro, 0, attr, depth)
  end

  private def mro_attr(mro : Array(Tuple(String, String)), index : Int32, attr : String, depth : Int32) : Array(Listed)?
    return if index >= mro.size
    file, name = mro[index]
    lines = read_file_lines(file) || return mro_attr(mro, index + 1, attr, depth)
    value = class_body_attr(lines, name, attr).try { |text| decorator_entries(text, file, depth) }
    module_attr_assignments(lines, name, attr).each do |op, text|
      entries = decorator_entries(text, file, depth)
      value = op == "=" ? entries : (value || mro_attr(mro, index + 1, attr, depth) || [] of Listed) + entries
    end
    value || mro_attr(mro, index + 1, attr, depth)
  end

  # The project classes class `name` in `file` lists as bases, in order.
  private def class_bases(file : String, name : String) : Array(Tuple(String, String))
    lines = read_file_lines(file) || return [] of Tuple(String, String)
    header = lines.find { |line| line.match(CLASS_DEF).try(&.[1]) == name } || return [] of Tuple(String, String)
    header.match(CLASS_DEF).try(&.[2]?).to_s.split(',').compact_map do |base|
      base = base.strip
      resolve_class(file, base) unless base.empty? || base.includes?('=')
    end
  end

  # The text assigned to `attr` in the body of class `name`.
  private def class_body_attr(lines : Array(String), name : String, attr : String) : String?
    start = lines.index { |line| line.match(CLASS_DEF).try(&.[1]) == name } || return
    idx = start + 1
    while idx < lines.size && (lines[idx].blank? || lines[idx][0].ascii_whitespace?)
      if (m = lines[idx].match(CLASS_DECORATORS)) && m[1] == attr
        return joined_value(lines, idx, m[2])
      end
      idx += 1
    end
    nil
  end

  # Module-level `Name.attr = [...]` / `Name.attr += [...]` statements, in
  # order, as `{operator, value text}`.
  private def module_attr_assignments(lines : Array(String), name : String, attr : String) : Array(Tuple(String, String))
    prefix = "#{name}.#{attr}"
    found = [] of Tuple(String, String)
    lines.each_with_index do |line, idx|
      next unless line.starts_with?(prefix)
      if m = line[prefix.size..].match(/^\s*(\+?=)(?!=)(.*)/)
        found << {m[1], joined_value(lines, idx, m[2])}
      end
    end
    found
  end

  private def joined_value(lines : Array(String), idx : Int32, text : String) : String
    while text.count("([{") > text.count(")]}") && (idx += 1) < lines.size
      text += lines[idx]
    end
    text
  end

  # The decorators a list expression names. Each is judged by its name
  # alone, as before its requirement was read, and read as written.
  private def decorator_entries(text : String, file : String, depth : Int32) : Array(Listed)
    # Strings blanked to their length keep each position in `code` one in `text`.
    code = text.gsub(PY_STRING) { |literal| " " * literal.size }
    entries = code.scan(/(?:^\s*[\[({]?|[\[,{:+])\s*([A-Za-z_][\w.]*)/).map do |m|
      args = call_arguments_after(code, m.end(1))
      # A flask-allows `requires(...)` entry keeps its requirements: what
      # they test decides how the guard is described.
      name = m[1].ends_with?("requires") && args ? "#{m[1]}#{args}" : m[1]
      {name, args ? "#{m[1]}#{text[m.end(1), args.size]}" : m[1]}
    end
    entries.flat_map do |name, source|
      if (ref = name.match(/^(.+)\.(method_decorators|decorators)$/)) && (target = resolve_class(file, ref[1]))
        class_attr(target[0], target[1], ref[2], depth + 1) || [] of Listed
      else
        [Listed.new(file, "@#{name}", "@#{source}")]
      end
    end
  end

  # The `(...)` call text starting at char `index` of `code`, if one does.
  private def call_arguments_after(code : String, index : Int32) : String?
    return unless code[index]? == '('
    depth = 0
    (index...code.size).each do |i|
      case code[i]
      when '(' then depth += 1
      when ')'
        depth -= 1
        return code[index..i] if depth == 0
      end
    end
    nil
  end

  private def resolve_class(file : String, name : String) : Tuple(String, String)?
    resolve(file, name) do |path, class_name|
      !!read_file_lines(path).try(&.any? { |line| line.match(CLASS_DEF).try(&.[1]) == class_name })
    end
  end

  private def decorator_description(line : String, file : String) : String?
    DECORATOR_PATTERNS.each do |pattern, desc|
      next unless line.matches?(pattern)
      # A FAB name means FAB's decorator only where the file imports it:
      # `from internal_lib.perm import has_access` is something else.
      next if desc.starts_with?("flask-appbuilder") && !read_file(file).try(&.includes?("flask_appbuilder"))
      next if desc.starts_with?("apifairy") && !read_file(file).try(&.matches?(APIFAIRY_IMPORT))
      return desc
    end
    nil
  end
end
