require "../../../models/framework_tagger"
require "../../../models/endpoint"

class FastAPIAuthTagger < FrameworkTagger
  # Depends() with auth-related callables
  DEPENDS_AUTH_PATTERNS = [
    {/Depends\s*\(\s*get_current_user/, "FastAPI Depends(get_current_user)"},
    {/Depends\s*\(\s*get_current_active_user/, "FastAPI Depends(get_current_active_user)"},
    {/Depends\s*\(\s*oauth2_scheme/, "FastAPI OAuth2 dependency"},
    {/Depends\s*\(\s*get_token/, "FastAPI token dependency"},
    {/Depends\s*\(\s*verify_token/, "FastAPI token verification"},
    {/Depends\s*\(\s*auth/, "FastAPI auth dependency"},
    {/Depends\s*\(\s*require_auth/, "FastAPI require_auth dependency"},
    {/Depends\s*\(\s*check_permission/, "FastAPI permission check"},
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

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "fastapi_auth"
  end

  def self.target_techs : Array(String)
    ["python_fastapi"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?

      # Check function signature and decorator for Depends/Security
      # ±2 line window: FastAPI auth deps are in the function signature or @app decorator,
      # kept tight to avoid matching patterns from adjacent route handlers
      start_idx = [line_num - 2, 0].max
      end_idx = [line_num + 2, lines.size - 1].min

      (start_idx..end_idx).each do |idx|
        line = lines[idx]

        DEPENDS_AUTH_PATTERNS.each do |pattern, desc|
          if line.matches?(pattern)
            endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "fastapi_auth"))
            return
          end
        end

        SECURITY_PATTERNS.each do |pattern, desc|
          if line.matches?(pattern)
            endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "fastapi_auth"))
            return
          end
        end

        AUTH_PARAM_PATTERNS.each do |pattern, desc|
          if line.matches?(pattern)
            endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "fastapi_auth"))
            return
          end
        end
      end
    end
  end
end
