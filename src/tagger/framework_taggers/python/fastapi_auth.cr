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

  def self.target_techs : Array(String)
    ["python_fastapi"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @auth_aliases = Hash(String, String).new
    @dependency_aliases = Hash(String, String).new
    @authz_dependencies = Set(String).new
    @file_aliases = Hash(String, Hash(String, String)).new
    @authz_defs = Hash(String, Set(String)).new
    @def_names = Hash(String, Set(String)).new
    @refusal_verdicts = Hash({String, String}, Bool?).new
    @soft_auth = nil.as(String?)
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @auth_aliases.clear
    @dependency_aliases.clear
    @authz_dependencies.clear
    @file_aliases.clear
    @authz_defs.clear
    @def_names.clear
    @refusal_verdicts.clear
    collect_files_by_extension(".py").each do |path|
      content = read_file(path)
      next unless content
      if content.includes?("Annotated")
        content.each_line do |line|
          next unless m = line.match(ANNOTATED_ALIAS)
          if desc = dependency_desc(m[2])
            @auth_aliases[m[1]] = desc
          end
          if dep = line.match(ANNOTATED_ALIAS_DEPENDENCY)
            @dependency_aliases[m[1]] = dep[2]
            (@file_aliases[path] ||= Hash(String, String).new)[m[1]] = dep[2]
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
        scopes.concat(router_statement(lines, receiver, path_info.path))
      end
      scopes.concat(class_dependencies(lines, line_num - 1, path_info.path))

      description = nil
      authz = nil
      scopes.each do |text, file|
        description ||= auth_desc(text, file)
        authz ||= authz_desc(text, file)
      end
      authz ||= body_authz_desc(lines, line_num - 1)
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
    return @refusal_verdicts[key] if @refusal_verdicts.has_key?(key)
    return if depth > 4
    @refusal_verdicts[key] = nil # cycle guard
    module_name, _, name = callable.rpartition('.')
    site = if module_name.empty?
             python_definition_site(path, name)
           elsif (symbol = python_imported_symbols(path)[module_name]?) && symbol[1].empty?
             python_definition_site(symbol[0], name)
           end
    verdict = nil
    if site && (body = definition_block(site[0], /^(?:async\s+)?def\s+#{Regex.escape(site[1])}\b/))
      if refusing_raise?(body, site[0]) || body.scan(DEPENDENCY_CALL).any? { |m| dependency_refuses?(m[2], site[0], depth + 1) == true }
        verdict = true
      elsif !body.matches?(/^\s*raise\b/m) && body.matches?(/^\s*return\s+None\s*$/m) &&
            body.match(RETURN_ANNOTATION).try(&.[1].matches?(/\bNone\b|\bOptional\b/))
        verdict = false
      end
    end
    @refusal_verdicts[key] = verdict
  end

  # A `raise` in `body` that answers 401/403: the status is on the raise
  # itself, the exception's name says so, or it raises a module-level
  # exception (`credentials_exception = HTTPException(status_code=401)`).
  # A 403 after a role / ownership read is authorization, which
  # `authz_desc` reports, not authentication.
  private def refusing_raise?(body : String, file : String) : Bool
    marker = body.matches?(AUTHZ_FIELD) ? UNAUTHENTICATED_MARKER : REFUSAL_MARKER
    body.each_line do |line|
      code = Analyzer::Python::Helper.strip_python_comment(line)
      next unless code.matches?(/^\s*raise\b/)
      return true if code.matches?(marker)
      if (name = code.match(/^\s*raise\s+(\w+)\s*(?:from\b.*)?$/).try(&.[1])) &&
         (site = python_definition_site(file, name)) &&
         (statement = definition_block(site[0], /^#{Regex.escape(site[1])}\s*(?::[^=\n]+)?=/))
        return true if statement.matches?(marker)
      end
    end
    false
  end

  # The top-level statement in `file` whose first line matches `start`:
  # through the last line indented under it, or until its brackets close
  # for an assignment.
  private def definition_block(file : String, start : Regex) : String?
    lines = read_file_lines(file) || return
    idx = lines.index(&.matches?(start)) || return
    String.build do |io|
      io << lines[idx] << '\n'
      depth = lines[idx].count('(') + lines[idx].count('[') - lines[idx].count(')') - lines[idx].count(']')
      ((idx + 1)...Math.min(lines.size, idx + 400)).each do |i|
        line = lines[i]
        break if depth <= 0 && !line.blank? && !line[0].ascii_whitespace? && !line.starts_with?(')')
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
    if callable = @file_aliases[path]?.try(&.[name]?)
      return {path, callable}
    end
    if (target = python_imported_symbols(path)[name]?) && (callable = @file_aliases[target[0]]?.try(&.[target[1]]?))
      return {target[0], callable}
    end
    {path, @dependency_aliases[name]?}
  end

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
  private def body_authz_desc(lines : Array(String), start : Int32) : String?
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
    while idx < lines.size && idx < start + 400
      line = lines[idx]
      break if !line.blank? && line.size - line.lstrip.size <= def_indent
      code = Analyzer::Python::Helper.strip_python_comment(line)
      if code.matches?(FORBIDDEN)
        return "FastAPI handler 403 check"
      elsif code.matches?(AUTHZ_FIELD)
        return "FastAPI handler ownership/role check"
      end
      idx += 1
    end
    nil
  end

  private def auth_desc(text : String, path : String) : String?
    # A dependency judged by its definition: one that refuses is a guard
    # whatever its name; one that admits anonymous callers is not, whatever
    # its name (`try_get_current_user` returning None).
    text.scan(DEPENDENCY_CALL) do |m|
      case dependency_refuses?(m[2], path)
      when true
        return "FastAPI #{m[1]}(#{m[2]})"
      when false
        @soft_auth ||= m[2] if auth_callable?(m[2])
        text = text.gsub(/#{Regex.escape(m[0])}\b/, "")
      end
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
      if desc = @auth_aliases[m[1]]?
        return "#{desc} (#{m[1]})"
      end
    end
    nil
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

  # `router = APIRouter(..., dependencies=[...])` (or `app = FastAPI(...)`)
  # for the decorator's receiver, as one statement, with the file to resolve
  # its names from. A receiver built from a project APIRouter subclass
  # (`UserRouter(prefix=...)` whose `__init__` pins `dependencies=`) also
  # brings that class's definition and those of its router bases.
  private def router_statement(lines : Array(String), receiver : String, path : String) : Array({String, String})
    scopes = [] of {String, String}
    receiver_re = /^#{Regex.escape(receiver)}\s*(?::\s*[\w.]+\s*)?=\s*([\w.]+)\s*\(/
    lines.each_with_index do |line, idx|
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
