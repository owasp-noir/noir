require "../../../models/framework_tagger"
require "../../../models/endpoint"

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

  def self.target_techs : Array(String)
    ["python_fastapi"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @auth_aliases = Hash(String, String).new
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @auth_aliases.clear
    collect_files_by_extension(".py").each do |path|
      content = read_file(path)
      next unless content && content.includes?("Annotated")
      content.each_line do |line|
        next unless (m = line.match(ANNOTATED_ALIAS)) && (desc = dependency_desc(m[2]))
        @auth_aliases[m[1]] = desc
      end
    end
    super
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
      if description.nil? && (receiver = header.match(ROUTE_DECORATOR).try(&.[1]))
        description = auth_desc(router_statement(lines, receiver))
      end
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "fastapi_auth"))
        return
      end
    end
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
  private def handler_header(lines : Array(String), start : Int32) : String
    String.build do |io|
      depth = 0
      seen_def = false
      idx = start
      while idx < lines.size && idx < start + 60
        line = lines[idx]
        io << line << '\n'
        seen_def ||= line.lstrip.matches?(/^(?:async\s+)?def\s/)
        depth += line.count('(') + line.count('[') - line.count(')') - line.count(']')
        break if seen_def && depth <= 0 && line.rstrip.ends_with?(':')
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
