require "../../../models/framework_tagger"
require "../../../models/endpoint"

class SwiftAuthTagger < FrameworkTagger
  # Vapor middleware patterns
  VAPOR_MIDDLEWARE_PATTERNS = [
    {/\.grouped\s*\(\s*\w*[Aa]uth\w*/, "Vapor auth middleware group"},
    {/\.grouped\s*\(\s*User\.authenticator\(\)/, "Vapor User.authenticator()"},
    {/\.grouped\s*\(\s*Token\.authenticator\(\)/, "Vapor Token.authenticator()"},
    {/\.grouped\s*\(\s*User\.guardMiddleware\(\)/, "Vapor User.guardMiddleware()"},
    {/\.grouped\s*\(\s*\w+\.guardMiddleware\(\)/, "Vapor guardMiddleware"},
    {/\.grouped\s*\(\s*BearerAuthenticator/, "Vapor BearerAuthenticator"},
    {/\.grouped\s*\(\s*BasicAuthenticator/, "Vapor BasicAuthenticator"},
    {/\.grouped\s*\(\s*SessionAuthenticator/, "Vapor SessionAuthenticator"},
  ]

  # Auth requirement in route handler
  HANDLER_AUTH_PATTERNS = [
    {/req\.auth\.require\s*\(/, "Vapor req.auth.require"},
    {/request\.auth\.require\s*\(/, "Vapor request.auth.require"},
    {/req\.auth\.get\s*\(/, "Vapor req.auth.get"},
    {/guard.*req\.auth/, "Vapor auth guard"},
  ]

  # Kitura patterns
  KITURA_AUTH_PATTERNS = [
    {/Credentials/, "Kitura Credentials middleware"},
    {/TypeSafeMiddleware/, "Kitura TypeSafeMiddleware"},
  ]

  # Hummingbird patterns
  HUMMINGBIRD_AUTH_PATTERNS = [
    {/\.add\s*\(\s*middleware:\s*\w*[Aa]uth\w*/, "Hummingbird auth middleware"},
    {/HBAuthenticator/, "Hummingbird HBAuthenticator"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "swift_auth"
  end

  def self.target_techs : Array(String)
    ["swift_vapor", "swift_kitura", "swift_hummingbird"]
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
      line_idx = line_num - 1

      # Check for auth middleware group wrapping this route
      description = check_middleware_group(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "swift_auth"))
        return
      end

      # Check route handler body for auth requirements
      description = check_handler_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "swift_auth"))
        return
      end
    end
  end

  private def check_middleware_group(lines : Array(String), route_line : Int32) : String?
    return nil if route_line < 0 || route_line >= lines.size

    route_line_text = lines[route_line].strip

    # Extract the receiver variable from the route line (e.g., "protected" from "protected.get(...)")
    receiver_match = route_line_text.match(/^(\w+)\.(get|post|put|delete|patch|group)/)
    return nil unless receiver_match
    receiver = receiver_match[1]

    # Walk backwards to find if this receiver was assigned from .grouped(AuthMiddleware)
    idx = route_line - 1
    while idx >= 0 && idx >= route_line - 20
      current = lines[idx]
      stripped = current.strip

      # Check if this line assigns the receiver variable from a .grouped() call
      # e.g., "let protected = app.grouped(UserAuthenticator())" — receiver must be "protected"
      assign_match = stripped.match(/(?:let|var)\s+(\w+)\s*=\s*\w+\.grouped\s*\(/)
      if assign_match && assign_match[1] == receiver
        all_patterns = VAPOR_MIDDLEWARE_PATTERNS + KITURA_AUTH_PATTERNS + HUMMINGBIRD_AUTH_PATTERNS
        all_patterns.each do |pattern, desc|
          return desc if stripped.matches?(pattern)
        end
      end

      # Stop at function/class definition
      break if stripped.starts_with?("func ") || stripped.starts_with?("class ") || stripped.starts_with?("struct ")

      idx -= 1
    end

    nil
  end

  private def check_handler_auth(lines : Array(String), route_line : Int32) : String?
    idx = route_line + 1
    end_idx = [route_line + 15, lines.size - 1].min
    brace_depth = 1 # We start inside the route closure's opening {

    while idx <= end_idx
      current = lines[idx]
      stripped = current.strip

      HANDLER_AUTH_PATTERNS.each do |pattern, desc|
        return desc if stripped.matches?(pattern)
      end

      # Track braces to stop at end of this route's closure
      brace_depth += current.count('{') - current.count('}')
      break if brace_depth <= 0

      idx += 1
    end

    nil
  end
end
