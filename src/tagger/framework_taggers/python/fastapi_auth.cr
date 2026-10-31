require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../analyzer/analyzers/python/python_helper"

@[Noir::TaggerFor(key: "fastapi_auth", name: "FastAPI Auth Tagger", desc: "Identifies FastAPI authentication patterns (Depends, Security, OAuth2)", order: 100)]
class FastAPIAuthTagger < FrameworkTagger
  # Depends() with auth-related callables
  DEPENDS_AUTH_PATTERNS = [
    {/Depends\s*\(\s*get_current_user\b/, "FastAPI Depends(get_current_user)"},
    {/Depends\s*\(\s*get_current_active_user\b/, "FastAPI Depends(get_current_active_user)"},
    {/Depends\s*\(\s*oauth2_scheme\b/, "FastAPI OAuth2 dependency"},
    {/Depends\s*\(\s*get_token\b/, "FastAPI token dependency"},
    {/Depends\s*\(\s*verify_token\b/, "FastAPI token verification"},
    {/Depends\s*\(\s*auth\b/, "FastAPI auth dependency"},
    {/Depends\s*\(\s*require_auth\b/, "FastAPI require_auth dependency"},
    {/Depends\s*\(\s*check_permission\b/, "FastAPI permission check"},
    {/Depends\s*\(\s*RoleChecker/, "FastAPI role checker"},
  ]

  # Security() declarations
  SECURITY_PATTERNS = [
    {/Security\s*\(\s*oauth2_scheme/, "FastAPI Security(oauth2_scheme)"},
    {/Security\s*\(\s*api_key/, "FastAPI Security(api_key)"},
    {/Security\s*\(\s*http_bearer/, "FastAPI Security(http_bearer)"},
    {/Security\s*\(\s*http_basic/, "FastAPI Security(http_basic)"},
  ]

  # Auth-related parameter type annotations
  AUTH_PARAM_PATTERNS = [
    {/:\s*User\s*=\s*Depends/, "FastAPI User dependency injection"},
    {/:\s*TokenData\s*=\s*Depends/, "FastAPI TokenData dependency"},
    {/:\s*HTTPAuthorizationCredentials\s*=\s*Security/, "FastAPI HTTP authorization"},
  ]

  # Any other `Depends(x)` / `Security(x)` whose callable is named for auth:
  # `get_current_active_superuser`, `reusable_oauth2`, `verify_api_key`, ...
  #
  # Matched on the name's snake/camel components, never as a substring:
  # `get_author_by_id` is not `auth`, and `get_token_count` / `get_roles_repo`
  # / `permission_service` fetch data rather than guard the route. The weak
  # words (token, role, permission) count only as the last component or before
  # a checker word (`verify_token`, `check_permissions`, `RoleChecker`).
  DEPENDENCY_CALL     = /\b(Depends|Security)\s*\(\s*([\w.]+)/
  NAME_COMPONENT      = /[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+/
  STRONG_AUTH_WORDS   = %w[auth authn authz authenticate authenticated authentication authorize authorized authorization oauth jwt bearer superuser login apikey]
  WEAK_AUTH_WORDS     = %w[token tokens role roles permission permissions scope scopes]
  AUTH_CHECKER_SUFFIX = %w[checker check required guard verifier validator]

  # `CurrentUser = Annotated[User, Depends(get_current_user)]`, the alias the
  # FastAPI docs and full-stack template annotate handler parameters with.
  ANNOTATED_ALIAS = /^\s*(\w+)\s*(?::\s*[\w.\[\]]+\s*)?=\s*Annotated\s*\[(.+)/

  ROUTE_DECORATOR = /^\s*@(\w+)\.(?:get|post|put|patch|delete|options|head|trace|api_route|websocket)\b/

  # Authorization, as opposed to authentication: a role / ownership field
  # being read, or the handler answering 403. A dependency counts only on
  # the field — `get_current_user` raises 403 for a bad token, which is
  # authentication — while a route body counts on either.
  # ponytail: `.permissions` / `.roles` may be a data read rather than a
  # check; a per-statement `if` parse would separate them.
  AUTHZ_FIELD                = /\.(?:is_superuser|is_admin|is_staff|owner_id|roles?|permissions?|scopes)\b/
  FORBIDDEN                  = /status_code\s*=\s*(?:403\b|status\.HTTP_403_FORBIDDEN)|\bHTTP_403_FORBIDDEN\b|HTTPException\s*\(\s*403\b/
  PYTHON_DEF                 = /^(?:async\s+)?def\s+(\w+)\s*\(/
  RETURN_ANNOTATION          = /\)\s*->\s*([^\n]+?)\s*:\s*$/m
  UNAUTHENTICATED_MARKER     = /\b401\b|\bHTTP_401_|Unauthori[sz]ed|NotAuthenticated|AuthenticationFailed/
  REFUSAL_MARKER             = /\b(?:401|403)\b|\bHTTP_40[13]_|Unauthori[sz]ed|Forbidden|NotAuthenticated|PermissionDenied|AuthenticationFailed/
  CLASS_DEF                  = /^(\s*)class\s+(\w+)\s*(?:\(([^)]*)\))?\s*:/
  CLASS_DEPENDENCY_ATTR      = /^\s*(\w+)\s*(?::[^=]+)?=\s*(?:Depends|Security)\s*\(/
  ANNOTATED_ALIAS_DEPENDENCY = /^\s*(\w+)\s*(?::\s*[\w.\[\]]+\s*)?=\s*Annotated\s*\[.*\bDepends\s*\(\s*([\w.]+)/

  alias Condition = {Int32, Bool, Bool, Bool}
  BODY_401_CHECK = "FastAPI handler 401 check"

  def self.target_techs : Array(String)
    ["python_fastapi"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @auth_aliases = Hash(String, String).new
    @dependency_aliases = Hash(String, String).new
    @authz_dependencies = Set(String).new
    @file_aliases = Hash(String, Hash(String, String)).new
    @alias_instances = Hash({String, String}, String).new
    @authz_defs = Hash(String, Set(String)).new
    @def_names = Hash(String, Set(String)).new
    @refusal_verdicts = Hash({String, String}, Bool?).new
    @instance_verdicts = Hash({String, String}, Bool?).new
    @alias_verdicts = Hash({String, String}, Bool).new
    @configurable_keys = Set(String).new
    @configurable = false
    @import_names = Hash(String, Set(String)).new
    @class_sites = Hash({String, String}, {String, Int32}?).new
    @soft_auth = nil.as(String?)
    @include_calls = [] of IncludeCall
    @includes_by_site = nil.as(Hash({String, String}, Array(IncludeCall))?)
    @include_scopes = Hash({String, String}, Array({String, String})).new
  end

  # `parent.include_router(target, ..., dependencies=[...])` in `file`.
  private record IncludeCall, file : String, parent : String, target : String, dependencies : String?
  # `self.app.include_router(...)` is indexed too: its parent never
  # resolves, so that mount counts as one without a dependency.
  INCLUDE_ROUTER_CALL = /^\s*([\w.]+?)\s*\.\s*include_router\s*\(/

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @auth_aliases.clear
    @dependency_aliases.clear
    @authz_dependencies.clear
    @file_aliases.clear
    @alias_instances.clear
    @authz_defs.clear
    @def_names.clear
    @refusal_verdicts.clear
    @instance_verdicts.clear
    @alias_verdicts.clear
    @configurable_keys.clear
    @import_names.clear
    @class_sites.clear
    @include_calls.clear
    @includes_by_site = nil
    @include_scopes.clear
    collect_files_by_extension(".py").each do |path|
      content = read_file(path)
      next unless content
      index_include_router_calls(path) if content.includes?("include_router")
      if content.includes?("Annotated")
        lines = content.lines
        lines.each_with_index do |line, idx|
          next unless line.includes?("Annotated")
          # `X = Annotated[\n    Subject, Depends(dep)\n]` read as one line.
          line = joined_statement(lines, idx) if line.count('[') > line.count(']')
          next unless m = line.match(ANNOTATED_ALIAS)
          if desc = dependency_desc(m[2])
            @auth_aliases[m[1]] = desc
          end
          if dep = line.match(ANNOTATED_ALIAS_DEPENDENCY)
            @dependency_aliases[m[1]] = dep[2]
            (@file_aliases[path] ||= Hash(String, String).new)[m[1]] = dep[2]
            # `Depends(Authenticator(...))`: the instance the call builds.
            if call = line.match(/\bDepends\s*\(\s*(#{Regex.escape(dep[2])}\s*\(.*)/)
              @alias_instances[{path, m[1]}] = "_ = #{call[1]}"
            end
          end
        end
      end
      index_authz_dependencies(path, content) if content.matches?(AUTHZ_FIELD)
    end
    super
  end

  # Top-level `def`s whose body checks a role / ownership field, per file
  # and (for the unresolved-import fallback) by bare name.
  private def index_authz_dependencies(path : String, content : String)
    name : String? = nil
    body = [] of String
    (content.lines << "").each do |line|
      if !line.blank? && line[0].ascii_whitespace?
        body << line if name
        next
      end
      if (current = name) && body.any?(&.matches?(AUTHZ_FIELD))
        @authz_dependencies << current
        (@authz_defs[path] ||= Set(String).new) << current
      end
      body.clear
      name = line.match(PYTHON_DEF).try(&.[1])
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    @soft_auth = nil
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      next if line_num < 1 || line_num > lines.size

      # The route's own decorators and `def` signature, wherever they wrap;
      # the `dependencies=[...]` of the APIRouter / FastAPI app it is
      # declared on (and of a project APIRouter subclass that router is);
      # and, for a method of a class-based view, the `Depends(...)` class
      # attributes injected into every route of that class.
      header = handler_header(lines, line_num - 1)
      scopes = [{header, path_info.path}]
      if receiver = header.match(ROUTE_DECORATOR).try(&.[1])
        scopes.concat(router_statement(lines, receiver, path_info.path, line_num - 1))
        scopes.concat(include_dependencies(path_info.path, receiver))
      end
      scopes.concat(class_dependencies(lines, line_num - 1, path_info.path))
      scopes.concat(scopes.flat_map { |text, file| dependency_variables(text, file) })

      description = nil
      authz = nil
      scopes.each do |text, file|
        description ||= auth_desc(text, file)
        authz ||= authz_desc(text, file)
      end
      authz ||= body_authz_desc(lines, line_num - 1, path_info.path)
      # Refusing a missing caller is authentication, not authorization.
      description, authz = (description || authz), nil if authz == BODY_401_CHECK
      next if description.nil? && authz.nil?

      endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "fastapi_auth")) if description
      endpoint.add_tag(Tag.new("authz", "Protected by #{authz}", "fastapi_auth")) if authz
      return
    end
    if soft = @soft_auth
      endpoint.add_tag(Tag.new("anonymous", "FastAPI Depends(#{soft}) admits anonymous callers: it returns None instead of refusing", "fastapi_auth"))
    end
  end

  # Whether the definition of dependency `callable`, used in `path`,
  # refuses the caller. true: its body raises a 401/403 (directly, by
  # raising a module-level exception built with one, or through a
  # `Depends(...)` of its own that refuses). false: it visibly admits an
  # anonymous caller: raises nothing, is annotated to return an Optional
  # and has a `return None`. nil: no definition, or nothing decisive.
  private def dependency_refuses?(callable : String, path : String, depth : Int32 = 0) : Bool?
    key = {callable, path}
    if @refusal_verdicts.has_key?(key)
      @configurable ||= @configurable_keys.includes?("dep\0#{callable}\0#{path}")
      return @refusal_verdicts[key]
    end
    return if depth > 4
    @refusal_verdicts[key] = nil # cycle guard
    module_name, _, name = callable.rpartition('.')
    site = if module_name.empty?
             python_definition_site(path, name)
           elsif (symbol = python_imported_symbols(path)[module_name]?) && symbol[1].empty?
             python_definition_site(symbol[0], name)
           end
    start = /^(?:async\s+)?def\s+#{Regex.escape(site[1])}\b/ if site
    # A dependency defined inside an app factory (`def create_app():`).
    # ponytail: any nested def of that name in the route's file, not the
    # one in the route's enclosing scope.
    if site.nil? && module_name.empty? && read_file(path).try(&.matches?(/^\s+(?:async\s+)?def\s+#{Regex.escape(name)}\b/m))
      site = {path, name}
      start = /^\s+(?:async\s+)?def\s+#{Regex.escape(name)}\b/
    end
    verdict = nil
    if site && start && (body = definition_block(site[0], start))
      if body_refuses?(body, site[0], depth, def_env(body, site[0], nil, Env.new, path))
        verdict = true
      elsif !body.matches?(/^\s*raise\b/m) && body.matches?(/^\s*return\s+None\s*$/m) &&
            body.match(RETURN_ANNOTATION).try(&.[1].matches?(/\bNone\b|\bOptional\b/))
        verdict = false
      end
    elsif site && (statement = definition_block(site[0], /^#{Regex.escape(site[1])}\s*(?::[^=\n]+)?=\s*[\w.]+\s*\(/))
      verdict = instance_refuses?(statement, site[0], depth)
    end
    @configurable_keys << "dep\0#{callable}\0#{path}" if @configurable
    @refusal_verdicts[key] = verdict
  end

  # Whether a `def` body refuses the caller: a 401/403 raise of its own,
  # or a dependency it declares that refuses (`dependency_refuses_in?`).
  private def body_refuses?(body : String, file : String, depth : Int32, env : Env = Env.new) : Bool
    refusing_raise?(body, file) || dependency_refuses_in?(body, file, depth, env)
  end

  # Whether a dependency `body` declares refuses: a `Depends(...)` of a
  # module-level dependency, of a call (`Depends(Authenticator(...))`,
  # judged as the instance it builds), of an instance assigned in the body
  # (Polar's `OrgPolicyGuard` factory depends on `_authenticator =
  # Authenticator(...)`), or the `Annotated` aliases its parameters, or a
  # nested dependency's, are typed with. `env` holds what the names in the
  # body are bound to.
  private def dependency_refuses_in?(body : String, file : String, depth : Int32, env : Env) : Bool
    body.scan(DEPENDENCY_CALL).any? do |m|
      call = m.post_match
      if call.starts_with?('(')
        instance_refuses?("_ = #{m[2]}#{call}", file, depth + 1, env) == true
      else
        local_instance_refuses?(body, m[2], file, depth + 1, env) || dependency_refuses?(m[2], file, depth + 1) == true
      end
    end || body.scan(ALIAS_ANNOTATION).any? { |m| alias_refuses?(m[1], file, depth + 1) }
  end

  private def local_instance_refuses?(body : String, name : String, file : String, depth : Int32, env : Env) : Bool
    return false if name.includes?('.') || !body.includes?(name)
    lines = body.lines
    idx = lines.index(&.matches?(/^\s+#{Regex.escape(name)}\s*=\s*[\w.]+\s*\(/)) || return false
    instance_refuses?(joined_statement(lines, idx), file, depth, env) == true
  end

  private def alias_refuses?(name : String, path : String, depth : Int32) : Bool
    # Only a top-level verdict is kept: one cut short by `depth` is not.
    return judge_alias(name, path, depth) unless depth == 0
    key = {path, name}
    if @alias_verdicts.has_key?(key)
      @configurable ||= @configurable_keys.includes?("alias\0#{path}\0#{name}")
      return @alias_verdicts[key]
    end
    @alias_verdicts[key] = false # cycle guard
    saved, @configurable = @configurable, false
    verdict = @alias_verdicts[key] = judge_alias(name, path, depth)
    @configurable_keys << "alias\0#{path}\0#{name}" if @configurable
    @configurable ||= saved
    verdict
  end

  private def judge_alias(name : String, path : String, depth : Int32) : Bool
    alias_path, callable = resolve_alias(name, path)
    return false unless callable
    # `Depends(OrgGuard(allowed_subjects={Anonymous, User}))`: the call's
    # arguments decide, not the factory at its defaults.
    if instance = @alias_instances[{alias_path, name.split('.').last}]?
      return instance_refuses?(instance, alias_path, depth) == true
    end
    dependency_refuses?(callable, alias_path, depth) == true
  end

  ALIAS_ANNOTATION = /:\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*(?=[,)=]|$)/m
  INSTANCE_CALL    = /=\s*([A-Za-z_][\w.]*)\s*\(/

  # What the names a dependency body reads are bound to: a parameter to the
  # value its call site passed (or its default), a local to the expression
  # assigned to it. `UNBOUND` marks a value nothing here decides.
  alias Env = Hash(String, String)
  UNBOUND = "\u0000"

  # A dependency that is an instance (`_BenefitsRead = Authenticator(...)`),
  # judged by its class's `__call__`, reached directly or through a factory
  # function's return annotation (`def Authenticator(...) -> _Authenticator`),
  # with the instance's arguments bound to the constructor's parameters. A
  # factory that returns a nested dependency instead (`OrgPolicyGuard(...)`)
  # is judged by its body under the call's arguments.
  #
  # true: it refuses an unidentified caller. The refusal must turn on the
  # caller (a credential or subject that is absent: `if not token`,
  # `if value is None`, `isinstance(subject, Anonymous)`, a failed decode),
  # and every instance setting on its path must hold for this instance:
  # `SubjectResolver(required=False)` never reaches `if self.required:
  # raise`, and `Authenticator({Anonymous, User})` returns before Polar's
  # `raise Unauthorized()`. A setting this scan cannot read (a constructor
  # flag from config) still reports the guard, noted as one a setting can
  # lift (`@configurable`). false: the class was read and refuses no
  # unidentified caller (a rate limit's or maintenance switch's 403 refuses
  # for another reason). nil: nothing decisive.
  private def instance_refuses?(statement : String, file : String, depth : Int32, env : Env = Env.new) : Bool?
    return if depth > 4
    key = {file, env.empty? ? statement : "#{statement}\u0000#{env.to_a.sort.join('\u0001')}"}
    flag = "inst\u0000#{key[0]}\u0000#{key[1]}"
    if @instance_verdicts.has_key?(key)
      @configurable ||= @configurable_keys.includes?(flag)
      return @instance_verdicts[key]
    end
    @instance_verdicts[key] = nil # cycle guard
    saved, @configurable = @configurable, false
    verdict = @instance_verdicts[key] = judge_instance(statement, file, depth, env)
    @configurable_keys << flag if @configurable
    @configurable ||= saved
    verdict
  end

  private def judge_instance(statement : String, file : String, depth : Int32, env : Env) : Bool?
    m = statement.match(INSTANCE_CALL) || return
    callee = m[1]
    args = call_arguments("(#{m.post_match}")
    if klass = class_site(file, callee)
      return judge_class(klass, bind_arguments(init_signature(klass), args, env, file, klass[0]), depth)
    end
    site = callable_site(file, callee) || return
    block = definition_block(site[0], /^(?:async\s+)?def\s+#{Regex.escape(site[1])}\b/) || return
    bound = bind_arguments(def_params(block), args, env, file, site[0])
    if klass = factory_class(file, callee)
      # The factory hands its parameters to the class by name.
      return judge_class(klass, bound, depth)
    end
    # A factory returning a nested dependency (`WebUserAuthorizer(scopes)`)
    # is judged by its body, which holds that dependency.
    return true if refusing_raise?(block, site[0])
    dependency_refuses_in?(block, site[0], depth + 1, def_env(block, site[0], bound, env, file)) ? true : nil
  end

  # The value each parameter of a `def` holds: `bound` (a call's arguments)
  # or its default, and each local the body assigns once.
  private def def_env(block : String, file : String, bound : Env?, caller_env : Env, caller_file : String) : Env
    env = bound || bind_arguments(def_params(block), [] of String, caller_env, caller_file, file)
    block.each_line do |line|
      if (assign = line.match(/^\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=(?!=)\s*(.+)$/)) && !env.has_key?(assign[1])
        env[assign[1]] = assign[2].strip
      end
    end
    env
  end

  private def callable_site(file : String, name : String) : {String, String}?
    module_name, _, short = name.rpartition('.')
    if module_name.empty?
      python_definition_site(file, short)
    elsif (symbol = python_imported_symbols(file)[module_name]?) && symbol[1].empty?
      python_definition_site(symbol[0], short)
    end
  end

  # The argument texts inside the parentheses `text` opens with.
  private def call_arguments(text : String) : Array(String)
    return [] of String unless text.starts_with?('(')
    depth = 0
    close = nil
    text.each_char_with_index do |char, idx|
      depth += 1 if char.in?('(', '[', '{')
      depth -= 1 if char.in?(')', ']', '}')
      if depth == 0
        close = idx
        break
      end
    end
    inner = text[1...(close || text.size)]
    Noir::TopLevelSplit.split(inner, ',', SPLIT_RULES).map(&.strip).reject(&.empty?)
  end

  # `{name, default}` for each parameter of the `def` that opens `block`,
  # `self` and `*`/`**` markers dropped.
  private def def_params(block : String) : Array({String, String?})
    header = block[0, block.index(/\)\s*(?:->[^\n:]*)?:\s*$/m) || block.size]
    args = call_arguments(header[(header.index('(') || 0)..] + ")")
    args.compact_map do |arg|
      next if arg == "*" || arg == "/" || arg.starts_with?("**")
      name = arg.lstrip('*').match(/\A[A-Za-z_]\w*/).try(&.[0]) || next
      next if name == "self" || name == "cls"
      default = arg.match(/=(?!=)\s*(.+)\z/m).try(&.[1].strip)
      {name, default}
    end
  end

  private def init_signature(klass : {String, Int32}) : Array({String, String?})
    method_body(klass, "__init__", 0).try { |body| def_params(body) } || [] of {String, String?}
  end

  # Each parameter bound to the value the call passes (evaluated where the
  # call is written) or to its default (evaluated where it is declared).
  private def bind_arguments(params : Array({String, String?}), args : Array(String), env : Env, file : String, callee_file : String) : Env
    bound = Env.new
    positional = 0
    args.each do |arg|
      next if arg.starts_with?('*')
      if kw = arg.match(/\A([A-Za-z_]\w*)\s*=(?!=)\s*(.+)\z/m)
        bound[kw[1]] = eval_expr(kw[2], env, file, 0) || UNBOUND
      else
        if param = params[positional]?
          bound[param[0]] = eval_expr(arg, env, file, 0) || UNBOUND
        end
        positional += 1
      end
    end
    params.each do |name, default|
      next if bound.has_key?(name)
      bound[name] = default.try { |text| eval_expr(text, Env.new, callee_file, 0) } || UNBOUND
    end
    bound
  end

  LITERAL = /\A(?:True|False|None|-?\d[\d_.]*|[rbuf]?(?:"[^"]*"|'[^']*'))\z/

  # `expr` as a literal, when the scan can tell: a literal itself, a
  # `set(...)` / `frozenset(...)` of one, `a or b`, a name bound in `env`, or
  # a module-level constant (`PUBLIC = {Anonymous, User}`). nil otherwise.
  private def eval_expr(expr : String, env : Env, file : String, depth : Int32) : String?
    expr = expr.strip
    return if depth > 8 || expr.empty? || expr == UNBOUND
    if (parts = top_level_or(expr)).size > 1
      value = nil
      parts.each do |part|
        value = eval_expr(part, env, file, depth + 1) || return
        return value unless falsy?(value)
      end
      return value
    end
    if wrapped = expr.match(/\A(?:frozenset|set|tuple|list)\((.*)\)\z/m)
      return wrapped[1].strip.empty? ? "()" : eval_expr(wrapped[1], env, file, depth + 1)
    end
    return expr if expr.matches?(LITERAL) || expr[0].in?('{', '[', '(')
    return unless expr.matches?(/\A[A-Za-z_]\w*\z/)
    if value = env[expr]?
      return eval_expr(value, env, file, depth + 1)
    end
    site = python_definition_site(file, expr) || return
    statement = definition_block(site[0], /^#{Regex.escape(site[1])}\s*(?::[^=\n]+)?=(?!=)/) || return
    rhs = statement.partition(/(?<![=!<>])=(?!=)/)[2]
    eval_expr(rhs, Env.new, site[0], depth + 1)
  end

  private def top_level_or(expr : String) : Array(String)
    parts = [] of String
    depth = 0
    last = 0
    i = 0
    while i < expr.size
      char = expr[i]
      depth += 1 if char.in?('(', '[', '{')
      depth -= 1 if char.in?(')', ']', '}')
      if depth == 0 && expr[i, 4]? == " or "
        parts << expr[last...i]
        last = i + 4
        i += 4
        next
      end
      i += 1
    end
    parts << expr[last..]
  end

  private def falsy?(value : String) : Bool
    value.in?("False", "None", "0", "\"\"", "''", "()", "[]", "{}")
  end

  # `__call__` judged for one instance, `bound` holding its constructor's
  # arguments. See `instance_refuses?`.
  private def judge_class(klass : {String, Int32}, bound : Env, depth : Int32) : Bool?
    body = call_method(klass, 0) || return
    attrs = instance_attrs(klass, bound)
    lines = body.lines
    caller_params = def_params(body).map(&.[0]).to_set
    locals = Hash(String, String).new
    lines.each { |line| line.match(/^\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=(?!=)\s*(.+)$/).try { |a| locals[a[1]] ||= a[2] } }
    marker = body.matches?(AUTHZ_FIELD) ? UNAUTHENTICATED_MARKER : REFUSAL_MARKER
    judged = false
    unread = false
    refusal_sites(lines, klass[0], marker).each do |idx, inline|
      judged = true
      conds = governing_conditions(lines, idx)
      conds << {inline, true} if inline
      caller = conds.empty?
      dead = false
      unknown = false
      conds.flat_map { |cond, positive| positive ? cond.split(/\s+and\s+/).map { |part| {part, true} } : [{cond, false}] }.each do |cond, positive|
        if cond.matches?(SETTING_REF)
          case setting_holds?(cond, positive, attrs)
          when false then dead = true
          when nil   then unknown = true
          end
        elsif caller_condition?(cond, caller_params, locals)
          caller ||= !presence?(cond, positive)
        else
          unknown = true
        end
      end
      next if dead || !caller
      return true unless unknown
      unread = true
    end
    if dependency_refuses_in?(body, klass[0], depth + 1, Env.new)
      return true
    end
    if unread
      @configurable = true
      return true
    end
    judged ? false : nil
  end

  # `self.x = expr` assignments of the class's `__init__` (or a base's),
  # evaluated for this instance.
  private def instance_attrs(klass : {String, Int32}, bound : Env) : Hash(String, String?)
    attrs = Hash(String, String?).new
    if init = method_body(klass, "__init__", 0)
      init.each_line { |line| line.match(/^\s+self\.([A-Za-z_]\w*)\s*(?::[^=\n]+)?=(?!=)\s*(.+)$/).try { |m| attrs[m[1]] ||= eval_expr(m[2], bound, klass[0], 0) } }
    end
    attrs
  end

  # `{line index, inline condition}` for each `raise` in a `__call__` body
  # that refuses (see `refusing_raise?`); an `if cond: raise ...` on one
  # line carries its condition.
  private def refusal_sites(lines : Array(String), file : String, marker : Regex) : Array({Int32, String?})
    sites = [] of {Int32, String?}
    lines.each_with_index do |line, idx|
      code = Analyzer::Python::Helper.strip_python_comment(line)
      inline = code.match(/^\s*(?:el)?if\s+(.+?):\s*(raise\b.*)$/)
      next unless inline || code.matches?(/^\s*raise\b/)
      statement = inline ? inline[2] : code
      cursor = idx
      depth = bracket_delta(statement)
      while depth > 0 && (cursor += 1) < lines.size
        part = Analyzer::Python::Helper.strip_python_comment(lines[cursor])
        depth += bracket_delta(part)
        statement = "#{statement} #{part.strip}"
      end
      sites << {idx, inline.try(&.[1])} if refusal_statement?(statement, file, marker)
    end
    sites
  end

  private def refusal_statement?(code : String, file : String, marker : Regex) : Bool
    return true if code.matches?(marker)
    name = code.match(/^\s*raise\s+(\w+)\s*(?:from\b.*)?$/).try(&.[1]) || return false
    site = python_definition_site(file, name) || return false
    statement = definition_block(site[0], /^#{Regex.escape(site[1])}\s*(?::[^=\n]+)?=/) || return false
    statement.matches?(marker)
  end

  # The conditions under which line `idx` of a body runs, each with the
  # branch taken: the enclosing `if`/`elif` (true) or `else` (its chain's
  # tests false), an enclosing `except` (`{"except", true}`), and earlier
  # sibling `if`s whose block returns (false: the line is reached past them).
  private def governing_conditions(lines : Array(String), idx : Int32) : Array({String, Bool})
    conds = [] of {String, Bool}
    threshold = lines[idx].size - lines[idx].lstrip.size
    j = idx - 1
    while j > 0
      line = Analyzer::Python::Helper.strip_python_comment(lines[j]).rstrip
      indent = line.size - line.lstrip.size
      stripped = line.strip
      if stripped.empty? || indent > threshold
        j -= 1
        next
      end
      break if stripped.matches?(/\A(?:async\s+)?def\b/)
      if indent == threshold
        if (sibling = stripped.match(/\A(?:if|elif)\s+(.+):\z/)) && block_returns?(lines, j, indent)
          conds << {sibling[1], false}
        end
      else
        if header = stripped.match(/\A(?:if|elif)\s+(.+):\z/)
          conds << {header[1], true}
        elsif stripped.starts_with?("else")
          chain_tests(lines, j, indent).each { |test| conds << {test, false} }
        elsif stripped.starts_with?("except")
          conds << {"except", true}
        end
        threshold = indent
      end
      j -= 1
    end
    conds
  end

  private def block_returns?(lines : Array(String), header : Int32, indent : Int32) : Bool
    ((header + 1)...lines.size).each do |k|
      line = lines[k]
      next if line.blank?
      return false if line.size - line.lstrip.size <= indent
      return true if line.lstrip.starts_with?("return")
    end
    false
  end

  # The `if`/`elif` tests of the chain an `else` at line `j` closes.
  private def chain_tests(lines : Array(String), j : Int32, indent : Int32) : Array(String)
    tests = [] of String
    k = j - 1
    while k > 0
      line = lines[k]
      k -= 1
      next if line.blank? || line.size - line.lstrip.size > indent
      break if line.size - line.lstrip.size < indent
      header = line.strip.match(/\A(if|elif)\s+(.+):\z/) || break
      tests << header[2]
      break if header[1] == "if"
    end
    tests
  end

  SETTING_REF  = /\bself\.[A-Za-z_]\w*\b(?!\s*\()/
  CALLER_TERMS = /\brequest\b|\b(?:token|credentials?|authorization|subject|principal|user|anonymous|session|api_?key|headers?|cookies?)\b|is_anonymous|Anonymous/i

  # Whether `cond` reads the caller: a term naming a credential or subject,
  # a `__call__` parameter (FastAPI injects each from the request), or a
  # local assigned from one of those.
  private def caller_condition?(cond : String, params : Set(String), locals : Hash(String, String)) : Bool
    return true if cond == "except" || cond.matches?(CALLER_TERMS)
    cond.scan(/(?<![\w.])[A-Za-z_]\w*/).any? do |word|
      name = word[0]
      params.includes?(name) || locals[name]?.try { |expr| expr.matches?(CALLER_TERMS) || expr.scan(/(?<![\w.])[A-Za-z_]\w*/).any? { |w| params.includes?(w[0]) } } || false
    end
  end

  # Whether taking the `positive` branch of `cond` means the caller's
  # credential or subject is there: `if token:` / `if user.is_banned:`
  # holding, `is not None`, or a failed `not token` / `is None` test. A
  # refusal there turns away someone who did identify (`403 if
  # user.unavailable`), not an anonymous caller. A mismatch (`x_key !=
  # KEY`), an `isinstance(subject, Anonymous)` or a failed decode is not.
  private def presence?(cond : String, positive : Bool) : Bool
    return false if cond == "except"
    present = cond.matches?(/\bis\s+not\s+None\b|!=\s*None\b/) || cond.strip.matches?(/\A[A-Za-z_][\w.]*\z/)
    absent = !present && cond.matches?(/\A\s*not\b|\bis\s+None\b|==\s*None\b|\bnot\s+in\b|is_anonymous|\bAnonymous\b/)
    positive ? present : absent
  end

  # Whether the `positive` branch of `cond`, a test of instance settings, is
  # taken for these attribute values: `X in self.attr`, `X not in
  # self.attr`, `self.attr`, `not self.attr`. nil when not decidable.
  private def setting_holds?(cond : String, positive : Bool, attrs : Hash(String, String?)) : Bool?
    truth = if m = cond.match(/\A\s*([A-Za-z_]\w*)\s+(not\s+)?in\s+self\.([A-Za-z_]\w*)\s*\z/)
              value = attrs[m[3]]? || return
              value.scan(/(?<![\w.])[A-Za-z_]\w*/).any?(&.[0].==(m[1])) != !m[2]?.nil?
            elsif m = cond.match(/\A\s*(not\s+)?self\.([A-Za-z_]\w*)\s*\z/)
              value = attrs[m[2]]? || return
              falsy?(value) == !m[1]?.nil?
            else
              return
            end
    truth == positive
  end

  private def setting_note(desc : String) : String
    @configurable ? "#{desc} (a setting can make it public)" : desc
  end

  # The body of method `name` in the class at `site`, or of the nearest base
  # defining one.
  private def method_body(site : {String, Int32}, name : String, depth : Int32) : String?
    return if depth > 4
    lines = read_file_lines(site[0]) || return
    header = lines[site[1]].match(CLASS_DEF) || return
    class_indent = header[1].size
    ((site[1] + 1)...lines.size).each do |idx|
      line = lines[idx]
      stripped = line.lstrip
      next if stripped.empty? || stripped.starts_with?('#')
      indent = line.size - stripped.size
      break if indent <= class_indent
      next unless stripped.matches?(/^(?:async\s+)?def\s+#{name}\b/)
      body = [line]
      lines[(idx + 1)..].each do |next_line|
        break if !next_line.blank? && next_line.size - next_line.lstrip.size <= indent && !next_line.lstrip.starts_with?(')')
        body << next_line
      end
      return body.join('\n')
    end
    class_bases(header[3]?).each do |base|
      next unless base_site = class_site(site[0], base)
      if found = method_body(base_site, name, depth + 1)
        return found
      end
    end
    nil
  end

  # The class a factory function `name` returns, by its return annotation.
  private def factory_class(file : String, name : String) : {String, Int32}?
    module_name, _, short = name.rpartition('.')
    site = if module_name.empty?
             python_definition_site(file, short)
           elsif (symbol = python_imported_symbols(file)[module_name]?) && symbol[1].empty?
             python_definition_site(symbol[0], short)
           end
    return unless site
    block = definition_block(site[0], /^(?:async\s+)?def\s+#{Regex.escape(site[1])}\b/) || return
    returned = block.match(RETURN_ANNOTATION).try(&.[1].match(/[A-Za-z_][\w.]*/).try(&.[0])) || return
    class_site(site[0], returned)
  end

  # The `__call__` body of the class at `site`, or of the nearest base
  # defining one.
  private def call_method(site : {String, Int32}, depth : Int32) : String?
    method_body(site, "__call__", depth)
  end

  # The statement starting at `lines[idx]`, continued until its brackets close.
  private def joined_statement(lines : Array(String), idx : Int32) : String
    text = lines[idx]
    depth = bracket_delta(text)
    cursor = idx
    while depth > 0 && (cursor += 1) < lines.size && cursor < idx + 40
      part = Analyzer::Python::Helper.strip_python_comment(lines[cursor])
      depth += bracket_delta(part)
      text = "#{text} #{part.strip}"
    end
    text
  end

  # A `raise` in `body` that answers 401/403: the status is on the raise
  # itself, the exception's name says so, or it raises a module-level
  # exception (`credentials_exception = HTTPException(status_code=401)`).
  # A 403 after a role / ownership read is authorization, which
  # `authz_desc` reports, not authentication.
  private def refusing_raise?(body : String, file : String) : Bool
    marker = body.matches?(AUTHZ_FIELD) ? UNAUTHENTICATED_MARKER : REFUSAL_MARKER
    lines = body.lines
    lines.each_with_index do |line, idx|
      code = Analyzer::Python::Helper.strip_python_comment(line)
      next unless code.matches?(/^\s*raise\b/)
      # A wrapped `raise HTTPException(\n status_code=401, ...)`.
      depth = bracket_delta(code)
      cursor = idx
      while depth > 0 && (cursor += 1) < lines.size
        part = Analyzer::Python::Helper.strip_python_comment(lines[cursor])
        depth += bracket_delta(part)
        code = "#{code} #{part.strip}"
      end
      return true if code.matches?(marker)
      if (name = code.match(/^\s*raise\s+(\w+)\s*(?:from\b.*)?$/).try(&.[1])) &&
         (site = python_definition_site(file, name)) &&
         (statement = definition_block(site[0], /^#{Regex.escape(site[1])}\s*(?::[^=\n]+)?=/))
        return true if statement.matches?(marker)
      end
    end
    false
  end

  # The statement in `file` whose first line matches `start`: through the
  # last line indented under it, or until its brackets close for an
  # assignment.
  private def definition_block(file : String, start : Regex) : String?
    lines = read_file_lines(file) || return
    idx = lines.index(&.matches?(start)) || return
    indent = lines[idx].size - lines[idx].lstrip.size
    String.build do |io|
      io << lines[idx] << '\n'
      depth = lines[idx].count('(') + lines[idx].count('[') - lines[idx].count(')') - lines[idx].count(']')
      ((idx + 1)...Math.min(lines.size, idx + 400)).each do |i|
        line = lines[i]
        break if depth <= 0 && !line.blank? && line.size - line.lstrip.size <= indent && !line.lstrip.starts_with?(')')
        io << line << '\n'
        depth += line.count('(') + line.count('[') - line.count(')') - line.count(']')
      end
    end
  end

  # `{statement, file}` for each `Depends(...)` class attribute a
  # class-based view (`@cbv(router)` / a project `@controller(router)`)
  # injects into the route method at `start`: the enclosing class's own and
  # those of its in-project bases, a subclass attribute shadowing a base
  # attribute of the same name.
  private def class_dependencies(lines : Array(String), start : Int32, path : String) : Array({String, String})
    indent = lines[start].size - lines[start].lstrip.size
    return [] of {String, String} if indent == 0
    (start - 1).downto(0) do |idx|
      line = lines[idx]
      stripped = line.lstrip
      next if stripped.empty? || stripped.starts_with?('#')
      next if line.size - stripped.size >= indent
      return [] of {String, String} unless line.matches?(CLASS_DEF)
      attrs = Hash(String, {String, String}).new
      collect_class_dependencies(path, idx, attrs, Set({String, Int32}).new)
      return attrs.values
    end
    [] of {String, String}
  end

  private def collect_class_dependencies(file : String, class_idx : Int32, attrs : Hash(String, {String, String}), seen : Set({String, Int32}))
    return if seen.size > 12 || !seen.add?({file, class_idx})
    lines = read_file_lines(file) || return
    header = lines[class_idx].match(CLASS_DEF) || return
    class_indent = header[1].size
    body_indent = nil
    ((class_idx + 1)...lines.size).each do |i|
      line = lines[i]
      stripped = line.lstrip
      next if stripped.empty? || stripped.starts_with?('#')
      line_indent = line.size - stripped.size
      break if line_indent <= class_indent
      body_indent ||= line_indent
      next unless line_indent == body_indent
      if attr = line.match(CLASS_DEPENDENCY_ATTR)
        attrs[attr[1]] = {line, file} unless attrs.has_key?(attr[1])
      end
    end
    class_bases(header[3]?).each do |base|
      next unless site = class_site(file, base)
      collect_class_dependencies(site[0], site[1], attrs, seen)
    end
  end

  # Base-class names of a `class X(A, mod.B[T], metaclass=M)` header.
  private def class_bases(list : String?) : Array(String)
    return [] of String unless list
    list.split(',').compact_map do |base|
      name = base.strip.sub(/\[.*\z/m, "")
      name unless name.empty? || name.includes?('=')
    end
  end

  # `{file, line index}` of the class definition `name` (`X` or `mod.X`)
  # refers to from `file`.
  private def class_site(file : String, name : String) : {String, Int32}?
    key = {file, name}
    return @class_sites[key] if @class_sites.has_key?(key)
    @class_sites[key] = find_class_site(file, name)
  end

  private def find_class_site(file : String, name : String) : {String, Int32}?
    module_name, _, class_name = name.rpartition('.')
    site = if module_name.empty?
             python_definition_site(file, class_name)
           elsif (symbol = python_imported_symbols(file)[module_name]?) && symbol[1].empty?
             python_definition_site(symbol[0], class_name)
           end
    return unless site
    lines = read_file_lines(site[0]) || return
    idx = lines.index(&.matches?(/^class\s+#{Regex.escape(site[1])}\b/)) || return
    {site[0], idx}
  end

  # Whether the class at `site` derives from APIRouter, through project
  # router classes.
  private def router_class?(site : {String, Int32}, depth : Int32 = 0) : Bool
    return false if depth > 6
    lines = read_file_lines(site[0]) || return false
    header = lines[site[1]].match(CLASS_DEF) || return false
    class_bases(header[3]?).any? do |base|
      base.split('.').last == "APIRouter" || (class_site(site[0], base).try { |s| router_class?(s, depth + 1) } || false)
    end
  end

  # A `Depends(x)` / `Security(x)` (or an `Annotated` alias of one) in
  # route file `path` whose definition checks a role / ownership field.
  private def authz_desc(text : String, path : String) : String?
    text.scan(DEPENDENCY_CALL) do |m|
      return "FastAPI #{m[1]}(#{m[2]})" if authz_dependency?(m[2], path)
    end
    text.scan(/:\s*(\w+)\b/) do |m|
      alias_path, callable = resolve_alias(m[1], path)
      if callable && authz_dependency?(callable, alias_path)
        return "FastAPI Depends(#{callable}) (#{m[1]})"
      end
    end
    nil
  end

  # The `Annotated` alias `name` as seen from `path`, with the file that
  # declares it: the same file, else the module it is imported from, else
  # any file declaring that alias name.
  private def resolve_alias(name : String, path : String) : Tuple(String, String?)
    module_name, _, leaf = name.rpartition('.')
    unless module_name.empty?
      symbol = python_imported_symbols(path)[module_name]?
      return {path, nil} unless symbol && symbol[1].empty?
      return {symbol[0], @file_aliases[symbol[0]]?.try(&.[leaf]?)}
    end
    if callable = @file_aliases[path]?.try(&.[name]?)
      return {path, callable}
    end
    if (target = python_imported_symbols(path)[name]?) && (callable = @file_aliases[target[0]]?.try(&.[target[1]]?))
      return {target[0], callable}
    end
    # `from vendor_sdk.types import Caller` is not the project's `Caller`.
    return {path, nil} if foreign_import?(path, name)
    {path, @dependency_aliases[name]?}
  end

  # Whether `path` imports `name` from somewhere (a module the scan may not
  # hold): then no same-named alias of another file is the one it uses.
  private def foreign_import?(path : String, name : String) : Bool
    return true if python_imported_symbols(path).has_key?(name)
    imports = @import_names[path] ||= begin
      names = Set(String).new
      (read_file(path) || "").scan(IMPORT_FROM) { |m| m[1].gsub(/[()]/, " ").split(',').each { |part| names << part.strip.split(/\s+as\s+/).last.strip } }
      names
    end
    imports.includes?(name)
  end

  IMPORT_FROM = /^\s*from\s+[\w.]+\s+import\s+(\([^)]*\)|[^\n]+)/m

  # `callable` (`x` or `deps.x`) resolved from `path`: the same file's
  # `def x`, else the module the file imports it from. When neither finds a
  # definition (a re-export through `__init__.py`, an import we cannot
  # resolve), fall back to the bare-name index, where two modules defining
  # the same name share one verdict.
  private def authz_dependency?(callable : String, path : String) : Bool
    module_name, _, name = callable.rpartition('.')
    file = nil
    if module_name.empty?
      if defines?(path, name)
        file = path
      elsif (symbol = python_imported_symbols(path)[name]?) && !symbol[1].empty?
        file, name = symbol
      end
    elsif (symbol = python_imported_symbols(path)[module_name]?) && symbol[1].empty?
      file = symbol[0]
    end
    if file && defines?(file, name)
      return !!@authz_defs[file]?.try(&.includes?(name))
    end
    @authz_dependencies.includes?(name)
  end

  private def defines?(path : String, name : String) : Bool
    names = @def_names[path] ||= begin
      set = Set(String).new
      read_file(path).try &.each_line { |line| line.match(PYTHON_DEF).try { |m| set << m[1] } }
      set
    end
    names.includes?(name)
  end

  # The handler's own body: from its `def` to the next line at or above
  # the `def`'s indent.
  private def body_authz_desc(lines : Array(String), start : Int32, path : String) : String?
    idx = start
    while idx < lines.size && idx < start + 60 && !lines[idx].lstrip.matches?(PYTHON_DEF)
      idx += 1
    end
    return if idx >= lines.size
    def_indent = lines[idx].size - lines[idx].lstrip.size
    # Skip the (possibly wrapped) signature: its closing `) -> T:` sits at
    # the `def`'s own indent.
    depth = 0
    while idx < lines.size && idx < start + 60
      code = Analyzer::Python::Helper.strip_python_comment(lines[idx]).rstrip
      depth += code.count('(') + code.count('[') - code.count(')') - code.count(']')
      idx += 1
      break if depth <= 0 && code.ends_with?(':')
    end
    callers = handler_caller_names(handler_header(lines, start), path)
    # A class-based view's injected caller, read as `self.user`.
    class_dependencies(lines, start, path).each do |statement, file|
      statement.scan(CALLER_PARAM) { |m| callers << "self.#{m[1]}" if m[2] == "Security" || caller_dependency?(m[3], file) }
    end
    # Open conditional blocks; `chain` holds, per indent, the flags of the
    # `if`/`elif` chain an `else` there would close.
    frames = [] of Condition
    chain = Hash(Int32, Condition).new
    while idx < lines.size && idx < start + 400
      line = lines[idx]
      idx += 1
      next if line.blank?
      indent = line.size - line.lstrip.size
      break if indent <= def_indent
      code = Analyzer::Python::Helper.strip_python_comment(line).strip
      depth = bracket_delta(code)
      while depth > 0 && idx < lines.size
        next_line = lines[idx]
        break if !next_line.blank? && next_line.size - next_line.lstrip.size <= def_indent
        part = Analyzer::Python::Helper.strip_python_comment(next_line).strip
        depth += bracket_delta(part)
        code = "#{code} #{part}"
        idx += 1
      end
      frames.reject! { |frame| frame[0] >= indent }
      chain.reject! { |level, _| level > indent }

      statement = code
      conditions = frames
      if m = code.match(BODY_IF)
        frame = condition_frame(indent, m[2], callers)
        if m[1]? && (prior = chain[indent]?)
          chain[indent] = {indent, prior[1] || frame[1], prior[2] || frame[2], false}
        else
          chain[indent] = frame
        end
        unless one_liner = m[3]?
          frames << frame
          next
        end
        statement = one_liner
        conditions = frames + [frame]
      elsif code.matches?(/^else\s*:/)
        # The `else` of a check runs exactly when the check fails, so a
        # None caller reaches it whatever the `if` short-circuits on.
        prior = chain.delete(indent)
        frames << {indent, prior.try(&.[1]) || false, prior.try(&.[2]) || false, false}
        next
      else
        chain.delete(indent)
        if m = code.match(/^while\s+(.+):$/)
          frames << condition_frame(indent, m[1], callers)
          next
        elsif code.matches?(/^except\b/)
          frames << {indent, false, false, false}
          next
        end
      end
      next unless statement.matches?(/^raise\b/) || statement.matches?(FORBIDDEN) || statement.matches?(UNAUTHORIZED_STATUS)
      if desc = refusal_desc(statement, conditions)
        return desc
      end
    end
    nil
  end

  BODY_IF             = /^(el)?if\s+(.+?):\s*(raise\b.*|return\b.*)?$/
  UNAUTHORIZED_STATUS = /status_code\s*=\s*(?:401\b|status\.HTTP_401_UNAUTHORIZED)/
  CALLER_REFERENCE    = /(?<![\w.])(?:request\.(?:state\.)?user\b|self\.[A-Za-z_]\w*|[A-Za-z_]\w*)/
  NONE_SKIPPING_TEST  = /^\(?\s*(request\.(?:state\.)?user|(?:self\.)?[A-Za-z_]\w*)(?:\s+is\s+not\s+None)?\s*(?:\band\b|\)?\s*$)/
  # Name components of a dependency that hands the route its caller.
  CALLER_WORDS = %w[user account principal identity viewer actor caller]

  # Net bracket depth of a line, ignoring brackets inside string literals.
  private def bracket_delta(code : String) : Int32
    depth = 0
    quote = nil.as(Char?)
    escaped = false
    code.each_char do |char|
      if q = quote
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == q
          quote = nil
        end
        next
      end
      case char
      when '"', '\''     then quote = char
      when '(', '[', '{' then depth += 1
      when ')', ']', '}' then depth -= 1
      end
    end
    depth
  end

  # A refusal in the handler body guards it only when an anonymous caller
  # is the one it refuses: it answers 403 unconditionally, or it sits under
  # a condition that reads the caller's role / ownership fields or the
  # caller itself, none of which a None caller short-circuits past.
  # `if not ENABLE_SIGNUP: raise 403` refuses everyone on a setting;
  # `if user and user.role != "admin": raise 403` lets anonymous through.
  private def refusal_desc(statement : String, conditions : Array(Condition)) : String?
    forbidden = statement.matches?(FORBIDDEN)
    if conditions.empty?
      return forbidden ? "FastAPI handler 403 check" : nil
    end
    return if conditions.any?(&.[3])
    if conditions.any?(&.[1])
      "FastAPI handler ownership/role check"
    elsif conditions.any?(&.[2]) && (forbidden || statement.matches?(REFUSAL_MARKER) || statement.matches?(UNAUTHORIZED_STATUS))
      forbidden ? "FastAPI handler 403 check" : BODY_401_CHECK
    end
  end

  # {indent, reads a role / ownership field?, reads the caller?, skipped
  # when the caller is None?} for one condition. Only the caller decides
  # the last: `if doc and doc.owner_id != user.id` still refuses anonymous.
  private def condition_frame(indent : Int32, condition : String, callers : Set(String)) : Condition
    reads_caller = condition.scan(CALLER_REFERENCE).any? { |m| callers.includes?(m[0]) || m[0].starts_with?("request.") }
    admits_none = (subject = condition.match(NONE_SKIPPING_TEST).try(&.[1])) &&
                  (callers.includes?(subject) || subject.starts_with?("request."))
    {indent, condition.matches?(AUTHZ_FIELD), reads_caller, !!admits_none}
  end

  CALLER_PARAM           = /(\w+)\s*(?::[^=,()]*(?:\[[^\]]*\][^=,()]*)?)?=\s*(Depends|Security)\s*\(\s*([\w.]*)/
  CALLER_ANNOTATED_PARAM = /(\w+)\s*:\s*Annotated\s*\[[^\n]*?\b(Depends|Security)\s*\(\s*([\w.]*)/
  CALLER_ALIAS_PARAM     = /(\w+)\s*:\s*(\w+)\s*[,)=]/

  # The handler parameters that inject the caller: a `Security(...)`, or a
  # `Depends(...)` (direct, in `Annotated[...]` or through an Annotated
  # alias) whose definition is judged as authentication, whose name reads
  # as auth, or that names who calls (`get_optional_user`). A session,
  # settings or form dependency is not the caller.
  private def handler_caller_names(header : String, path : String) : Set(String)
    names = Set(String).new
    {CALLER_PARAM, CALLER_ANNOTATED_PARAM}.each do |re|
      header.scan(re) { |m| names << m[1] if m[2] == "Security" || caller_dependency?(m[3], path) }
    end
    header.scan(CALLER_ALIAS_PARAM) do |m|
      if @auth_aliases.has_key?(m[2])
        names << m[1]
      elsif (callee = @dependency_aliases[m[2]]?) && caller_dependency?(callee, path)
        names << m[1]
      end
    end
    names
  end

  private def caller_dependency?(callee : String, path : String) : Bool
    return false if callee.empty?
    return true unless dependency_refuses?(callee, path).nil?
    name = callee.split('.').last
    auth_callable?(name) || name.scan(NAME_COMPONENT).any? { |m| CALLER_WORDS.includes?(m[0].downcase) }
  end

  private def auth_desc(text : String, path : String) : String?
    # A dependency judged by its definition: one that refuses is a guard
    # whatever its name; one that admits anonymous callers is not, whatever
    # its name (`try_get_current_user` returning None).
    text.scan(DEPENDENCY_CALL) do |m|
      call = m.post_match
      @configurable = false
      # `Depends(Authenticator(allowed_subjects={User}))`: the instance the
      # call builds, judged with its arguments.
      verdict = call.starts_with?('(') ? instance_refuses?("_ = #{m[2]}#{call}", path, 0) : dependency_refuses?(m[2], path)
      case verdict
      when true
        return setting_note("FastAPI #{m[1]}(#{m[2]}#{"(...)" if call.starts_with?('(')})")
      when false
        @soft_auth ||= m[2] if auth_callable?(m[2])
        text = text.gsub(/#{Regex.escape(m[0])}\b/, "")
      end
    end
    # `auth_subject: auth.BenefitsRead`: an `Annotated` alias judged by its
    # dependency's definition.
    text.scan(ALIAS_ANNOTATION) do |m|
      @configurable = false
      if alias_refuses?(m[1], path, 0)
        return setting_note("FastAPI Depends(#{resolve_alias(m[1], path)[1]}) (#{m[1].split('.').last})")
      end
    end
    if factory = factory_dependency_desc(text, path)
      return factory
    end
    {DEPENDS_AUTH_PATTERNS, SECURITY_PATTERNS, AUTH_PARAM_PATTERNS}.each do |patterns|
      patterns.each do |pattern, desc|
        return desc if text.matches?(pattern)
      end
    end
    if desc = dependency_desc(text)
      return desc
    end
    text.scan(/:\s*(\w+)\b/) do |m|
      next if foreign_import?(path, m[1])
      if desc = @auth_aliases[m[1]]?
        return "#{desc} (#{m[1]})"
      end
    end
    nil
  end

  DEPENDENCIES_LIST = /\bdependencies\s*=\s*\[([^\]]*)\]/m
  FACTORY_ITEM      = /\A([A-Za-z_][\w.]*)\s*\(/
  RETURNED_DEPENDS  = /^\s*return\s+(?:Depends|Security)\s*\(\s*(?:dependency\s*=\s*)?(\w+)\s*[,)]/
  BARE_RETURN       = /^\s*return(?:\s+None)?\s*$/
  SPLIT_RULES       = Noir::TopLevelSplit::Rules.new

  # `dependencies=[make_auth(settings.token)]`: a call that builds the
  # dependency, judged by the nested function whose `Depends(...)` it
  # returns. A refusal its own argument can switch off
  # (`if expected_token is None: return`) is one a setting can lift.
  private def factory_dependency_desc(text : String, path : String) : String?
    text.scan(DEPENDENCIES_LIST) do |list|
      Noir::TopLevelSplit.split(list[1], ',', SPLIT_RULES).each do |item|
        name = item.match(FACTORY_ITEM).try(&.[1])
        next if name.nil? || name.in?("Depends", "Security")
        module_name, _, short = name.rpartition('.')
        site = if module_name.empty?
                 python_definition_site(path, short)
               elsif (symbol = python_imported_symbols(path)[module_name]?) && symbol[1].empty?
                 python_definition_site(symbol[0], short)
               end
        next unless site && (body = definition_block(site[0], /^(?:async\s+)?def\s+#{Regex.escape(site[1])}\b/))
        body_lines = body.lines
        next unless inner = body_lines.compact_map { |line| line.match(RETURNED_DEPENDS).try(&.[1]) }.first?
        next unless inner_idx = body_lines.index(&.matches?(/^\s+(?:async\s+)?def\s+#{Regex.escape(inner)}\b/))
        inner_indent = body_lines[inner_idx].size - body_lines[inner_idx].lstrip.size
        inner_lines = [body_lines[inner_idx]]
        # The signature may wrap, its `) -> None:` back at the def's indent.
        depth = bracket_delta(Analyzer::Python::Helper.strip_python_comment(body_lines[inner_idx]))
        body_lines[(inner_idx + 1)..].each do |line|
          break if depth <= 0 && !line.blank? && line.size - line.lstrip.size <= inner_indent
          depth += bracket_delta(Analyzer::Python::Helper.strip_python_comment(line)) if depth > 0
          inner_lines << line
        end
        next unless refusing_raise?(inner_lines.join('\n'), site[0])
        params = body_lines[0].match(/\(([^)]*)\)/).try(&.[1].split(',').map(&.split(/[:=]/, 2)[0].strip).reject(&.empty?)) || [] of String
        return "FastAPI #{name}(...)#{" (a setting can make it public)" if setting_lifted?(inner_lines, params)}"
      end
    end
    nil
  end

  # An `if` on one of `params` whose block is a bare `return`, before any
  # `raise`: the factory's argument lets every caller through.
  private def setting_lifted?(lines : Array(String), params : Array(String)) : Bool
    lines.each_with_index do |line, idx|
      code = Analyzer::Python::Helper.strip_python_comment(line)
      return false if code.matches?(/^\s*raise\b/)
      next unless cond = code.match(/^\s*if\s+(.+):\s*(return(?:\s+None)?)?\s*$/)
      words = cond[1].scan(CALLER_REFERENCE).map(&.[0])
      next unless params.any? { |param| words.includes?(param) }
      return true if cond[2]? || lines[idx + 1..].find { |next_line| !next_line.blank? }.try(&.matches?(BARE_RETURN))
    end
    false
  end

  private def dependency_desc(text : String) : String?
    text.scan(DEPENDENCY_CALL) do |m|
      return "FastAPI #{m[1]}(#{m[2]})" if auth_callable?(m[2])
    end
    nil
  end

  private def auth_callable?(name : String) : Bool
    words = name.scan(NAME_COMPONENT).map(&.[0].downcase)
    words.each_with_index.any? do |word, i|
      nxt = words[i + 1]?
      STRONG_AUTH_WORDS.includes?(word) ||
        (word == "api" && nxt == "key") ||
        (word == "current" && words[i + 1..].any? { |w| w == "user" || w == "superuser" }) ||
        (WEAK_AUTH_WORDS.includes?(word) && (nxt.nil? || AUTH_CHECKER_SUFFIX.includes?(nxt)))
    end
  end

  # From the route's first decorator line through the end of its `def`
  # signature (the line where the parentheses balance and it ends in `:`).
  # Comments are dropped first, so `async def x():  # note` still ends the
  # signature. A one-line `def x(): return ...` never ends in `:`, so the
  # next decorator or `def` at the handler's level ends it instead: that
  # line belongs to the next handler, whose `Depends(...)` is not this one's.
  private def handler_header(lines : Array(String), start : Int32) : String
    String.build do |io|
      depth = 0
      def_indent : Int32? = nil
      idx = start
      while idx < lines.size && idx < start + 60
        line = Analyzer::Python::Helper.strip_python_comment(lines[idx]).rstrip
        stripped = line.lstrip
        indent = line.size - stripped.size
        opens_def = stripped.matches?(/^(?:async\s+)?def\s/)
        if (level = def_indent) && indent <= level && (opens_def || stripped.starts_with?('@'))
          break
        end
        io << line << '\n'
        def_indent ||= indent if opens_def
        depth += line.count('(') + line.count('[') - line.count(')') - line.count(']')
        break if def_indent && depth <= 0 && line.ends_with?(':')
        idx += 1
      end
    end
  end

  private def index_include_router_calls(path : String)
    lines = read_file_lines(path) || return
    lines.each_with_index do |line, idx|
      next unless parent = line.match(INCLUDE_ROUTER_CALL).try(&.[1])
      statement = String.build do |io|
        depth = 0
        lines[idx, 30].each do |part|
          code = Analyzer::Python::Helper.strip_python_comment(part)
          io << code << '\n'
          depth += bracket_delta(code)
          break if depth <= 0
        end
      end
      args = statement.sub(INCLUDE_ROUTER_CALL, "").rstrip.rchop(')')
      parts = Noir::TopLevelSplit.split(args, ',', SPLIT_RULES).map(&.strip)
      target = parts.find { |part| part.starts_with?("router") && part.matches?(/\Arouter\s*=/) }.try(&.sub(/\Arouter\s*=\s*/, "")) ||
               parts.find { |part| !part.empty? && !part.includes?('=') }
      next unless target && target.matches?(/\A[\w.]+\z/)
      dependencies = parts.find(&.matches?(/\Adependencies\s*=/))
      @include_calls << IncludeCall.new(path, parent, target, dependencies)
    end
  end

  # The `dependencies=[...]` of every `include_router(...)` that mounts the
  # router `receiver` defined in `path`, directly or through the routers
  # that include it in turn: FastAPI runs them for each included route. A
  # router mounted more than once counts only when every mount path carries
  # an auth dependency, since its routes are served under each.
  private def include_dependencies(path : String, receiver : String) : Array({String, String})
    key = {path, receiver}
    if cached = @include_scopes[key]?
      return cached
    end
    @include_scopes[key] = [] of {String, String} # cycle guard
    by_site = @includes_by_site ||= @include_calls.each_with_object(Hash({String, String}, Array(IncludeCall)).new) do |call, index|
      if site = include_target_site(call)
        (index[site] ||= [] of IncludeCall) << call
      end
    end
    chains = (by_site[key]? || [] of IncludeCall).map do |call|
      chain = include_dependencies(call.file, call.parent).dup
      call.dependencies.try { |dependencies| chain.unshift({dependencies, call.file}) }
      chain
    end
    soft = @soft_auth
    guarded = chains.all? { |chain| chain.any? { |text, file| auth_desc(text, file) || authz_desc(text, file) } }
    @soft_auth = soft
    @include_scopes[key] = guarded ? chains.flat_map(&.itself) : [] of {String, String}
  end

  # `{file, name}` of the router an include call's target refers to.
  private def include_target_site(call : IncludeCall) : {String, String}?
    module_name, _, name = call.target.rpartition('.')
    if module_name.empty?
      python_definition_site(call.file, name)
    elsif (symbol = python_imported_symbols(call.file)[module_name]?) && symbol[1].empty?
      python_definition_site(symbol[0], name)
    end
  end

  # The assignment each bare name in a `dependencies=[...]` list is bound
  # to (`internal = Depends(require_internal)`; `dependencies=[internal]`),
  # with the file that declares it.
  private def dependency_variables(text : String, path : String) : Array({String, String})
    found = [] of {String, String}
    text.scan(DEPENDENCIES_LIST) do |list|
      Noir::TopLevelSplit.split(list[1], ',', SPLIT_RULES).each do |item|
        name = item.strip
        next unless name.matches?(/\A[A-Za-z_][\w.]*\z/)
        module_name, _, leaf = name.rpartition('.')
        site = if module_name.empty?
                 python_definition_site(path, leaf)
               elsif (symbol = python_imported_symbols(path)[module_name]?) && symbol[1].empty?
                 python_definition_site(symbol[0], leaf)
               end
        next unless site
        statement = definition_block(site[0], /^#{Regex.escape(site[1])}\s*(?::[^=\n]+)?=\s*(?:Depends|Security)\s*\(/) || next
        found << {statement, site[0]}
      end
    end
    found
  end

  # `router = APIRouter(..., dependencies=[...])` (or `app = FastAPI(...)`)
  # for the decorator's receiver, as one statement, with the file to resolve
  # its names from. A receiver built from a project APIRouter subclass
  # (`UserRouter(prefix=...)` whose `__init__` pins `dependencies=`) also
  # brings that class's definition and those of its router bases.
  #
  # A route declared inside a function (a router factory) uses the nearest
  # assignment above it in an enclosing scope.
  # The nearest assignment to `receiver` in the scope of the statement at
  # `idx` or an enclosing one: each `def` / `class` above it at a smaller
  # indent opens the next scope out, whose statements sit at that indent.
  private def local_assignment(lines : Array(String), idx : Int32, receiver : String, receiver_re : Regex) : Int32?
    scope = lines[idx].size - lines[idx].lstrip.size
    (idx - 1).downto(0) do |i|
      stripped = lines[i].lstrip
      next if stripped.empty?
      indent = lines[i].size - stripped.size
      if indent < scope && stripped.matches?(/^(?:async\s+def|def|class)\s/)
        scope = indent
      elsif indent == scope && stripped.starts_with?(receiver) && stripped.matches?(receiver_re)
        return i
      end
      break if scope == 0
    end
    nil
  end

  private def router_statement(lines : Array(String), receiver : String, path : String, route_idx : Int32) : Array({String, String})
    scopes = [] of {String, String}
    receiver_re = /^#{Regex.escape(receiver)}\s*(?::\s*[\w.]+\s*)?=\s*([\w.]+)\s*\(/
    route_indent = lines[route_idx].size - lines[route_idx].lstrip.size
    local = local_assignment(lines, route_idx, receiver, receiver_re) if route_indent > 0
    (local ? [local] : (0...lines.size)).each do |idx|
      line = local ? lines[idx].lstrip : lines[idx]
      next unless line.starts_with?(receiver) && (ctor = line.match(receiver_re).try(&.[1]))
      ctor_name = ctor.split('.').last
      router_class = nil
      unless ctor_name == "APIRouter" || ctor_name == "FastAPI"
        router_class = class_site(path, ctor)
        next unless router_class && router_class?(router_class)
      end
      statement = String.build do |io|
        depth = 0
        lines[idx, 30].each do |part|
          io << part << '\n'
          depth += part.count('(') + part.count('[') - part.count(')') - part.count(']')
          break if depth <= 0
        end
      end
      scopes << {statement, path}
      site = router_class
      hops = 0
      while site && hops < 6
        file_lines = read_file_lines(site[0]) || break
        header = file_lines[site[1]].match(CLASS_DEF) || break
        if block = definition_block(site[0], /^class\s+#{Regex.escape(header[2])}\b/)
          scopes << {block, site[0]}
        end
        current = site
        site = class_bases(header[3]?).compact_map { |base| class_site(current[0], base) }.find { |s| router_class?(s) }
        hops += 1
      end
      break
    end
    scopes
  end
end
