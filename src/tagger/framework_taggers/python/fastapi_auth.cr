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
  ANNOTATED_ALIAS_DEPENDENCY = /^\s*(\w+)\s*(?::\s*[\w.\[\]]+\s*)?=\s*Annotated\s*\[.*\bDepends\s*\(\s*([\w.]+)/

  def self.target_techs : Array(String)
    ["python_fastapi"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @auth_aliases = Hash(String, String).new
    @dependency_aliases = Hash(String, String).new
    @authz_dependencies = Set(String).new
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @auth_aliases.clear
    @dependency_aliases.clear
    @authz_dependencies.clear
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
          end
        end
      end
      index_authz_dependencies(content) if content.matches?(AUTHZ_FIELD)
    end
    super
  end

  # Top-level `def`s whose body checks a role / ownership field, by bare
  # name. ponytail: names are not scoped to their module, so two modules
  # defining the same dependency name share one verdict.
  private def index_authz_dependencies(content : String)
    name : String? = nil
    body = [] of String
    (content.lines << "").each do |line|
      if !line.blank? && line[0].ascii_whitespace?
        body << line if name
        next
      end
      if (current = name) && body.any?(&.matches?(AUTHZ_FIELD))
        @authz_dependencies << current
      end
      body.clear
      name = line.match(PYTHON_DEF).try(&.[1])
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      next if line_num < 1 || line_num > lines.size

      # The route's own decorators and `def` signature, wherever they wrap,
      # and the `dependencies=[...]` of the APIRouter / FastAPI app it is
      # declared on.
      header = handler_header(lines, line_num - 1)
      description = auth_desc(header)
      authz = authz_desc(header)
      if (description.nil? || authz.nil?) && (receiver = header.match(ROUTE_DECORATOR).try(&.[1]))
        router = router_statement(lines, receiver)
        description ||= auth_desc(router)
        authz ||= authz_desc(router)
      end
      authz ||= body_authz_desc(lines, line_num - 1)
      next if description.nil? && authz.nil?

      endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "fastapi_auth")) if description
      endpoint.add_tag(Tag.new("authz", "Protected by #{authz}", "fastapi_auth")) if authz
      return
    end
  end

  # A `Depends(x)` / `Security(x)` (or an `Annotated` alias of one) whose
  # definition checks a role / ownership field.
  private def authz_desc(text : String) : String?
    text.scan(DEPENDENCY_CALL) do |m|
      return "FastAPI #{m[1]}(#{m[2]})" if authz_dependency?(m[2])
    end
    text.scan(/:\s*(\w+)\b/) do |m|
      if (callable = @dependency_aliases[m[1]]?) && authz_dependency?(callable)
        return "FastAPI Depends(#{callable}) (#{m[1]})"
      end
    end
    nil
  end

  private def authz_dependency?(callable : String) : Bool
    @authz_dependencies.includes?(callable.split('.').last)
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

  private def auth_desc(text : String) : String?
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
  # for the decorator's receiver, as one statement.
  private def router_statement(lines : Array(String), receiver : String) : String
    lines.each_with_index do |line, idx|
      next unless line.starts_with?(receiver) && line.matches?(/^#{Regex.escape(receiver)}\s*(?::\s*\w+\s*)?=\s*(?:fastapi\.)?(?:APIRouter|FastAPI)\s*\(/)
      return String.build do |io|
        depth = 0
        lines[idx, 30].each do |part|
          io << part << '\n'
          depth += part.count('(') + part.count('[') - part.count(')') - part.count(']')
          break if depth <= 0
        end
      end
    end
    ""
  end
end
