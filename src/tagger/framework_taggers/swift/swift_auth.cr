require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "swift_auth", name: "Swift Auth Tagger", desc: "Identifies Vapor/Kitura/Hummingbird authentication patterns", order: 220)]
class SwiftAuthTagger < FrameworkTagger
  # `.group(` / `.grouped(` followed by any earlier arguments, so a pattern
  # after it matches at the start of ANY argument:
  # `app.grouped(UserToken.authenticator(), User.guardMiddleware())` is
  # guarded by its second one. `.group(...) { name in` is the closure form.
  GROUPED_ARG = /\.group(?:ed)?\s*\((?:[^(),]*(?:\([^()]*\)[^(),]*)?,\s*)*\s*/.source

  # Vapor middleware patterns
  VAPOR_MIDDLEWARE_PATTERNS = [
    {/#{GROUPED_ARG}\w*[Aa]uth\w*/, "Vapor auth middleware group"},
    {/#{GROUPED_ARG}User\.authenticator\(\)/, "Vapor User.authenticator()"},
    {/#{GROUPED_ARG}Token\.authenticator\(\)/, "Vapor Token.authenticator()"},
    {/#{GROUPED_ARG}User\.guardMiddleware\(\)/, "Vapor User.guardMiddleware()"},
    {/#{GROUPED_ARG}\w+\.guardMiddleware\(\)/, "Vapor guardMiddleware"},
    # After the guardMiddleware patterns so
    # `grouped(UserToken.authenticator(), User.guardMiddleware())` keeps the
    # guard description. `UserToken` has no `[Aa]uth` and is neither `User.`
    # nor `Token.`.
    {/#{GROUPED_ARG}UserToken\.authenticator\(\)/, "Vapor UserToken.authenticator()"},
    {/#{GROUPED_ARG}BearerAuthenticator/, "Vapor BearerAuthenticator"},
    {/#{GROUPED_ARG}BasicAuthenticator/, "Vapor BasicAuthenticator"},
    {/#{GROUPED_ARG}SessionAuthenticator/, "Vapor SessionAuthenticator"},
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

  def self.target_techs : Array(String)
    ["swift_vapor", "swift_kitura", "swift_hummingbird"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError, and
      # line 0 would otherwise scan the wrong region via lines[-1].
      next if line_num < 1 || line_num > lines.size
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
    return if route_line < 0 || route_line >= lines.size

    # Extract the receiver variable from the route line (e.g., "protected" from "protected.get(...)")
    receiver_match = lines[route_line].strip.match(/^(\w+)\.(?:get|post|put|delete|patch|on|group)\b/)
    return unless receiver_match
    receiver = receiver_match[1]

    # The binding may sit anywhere in this function (`let x = app.grouped(...)`
    # or `group(...) { x in`). Stop at the enclosing func/type so a same-named
    # receiver in the previous function is not this route's guard.
    idx = route_line - 1
    while idx >= 0
      stripped = lines[idx].strip
      break if function_boundary?(stripped)

      if binds_receiver?(stripped, receiver)
        return middleware_description(stripped)
      end

      idx -= 1
    end

    nil
  end

  private def function_boundary?(line : String) : Bool
    line.matches?(/^(?:(?:public|private|internal|open|fileprivate|final|override|static|class|mutating|nonmutating)\s+)*func\b/) ||
      line.matches?(/^(?:(?:public|private|internal|open|fileprivate|final|override)\s+)*(?:class|struct|enum|extension|actor|protocol)\b/)
  end

  private def binds_receiver?(line : String, receiver : String) : Bool
    if assign = line.match(/(?:let|var)\s+(\w+)\s*=\s*.*\.group(?:ed)?\s*\(/)
      return true if assign[1] == receiver
    end

    return false unless line.matches?(/\.group(?:ed)?\s*\(/)
    line.matches?(/\{\s*#{Regex.escape(receiver)}\s+in\b/)
  end

  private def middleware_description(line : String) : String?
    (VAPOR_MIDDLEWARE_PATTERNS + KITURA_AUTH_PATTERNS + HUMMINGBIRD_AUTH_PATTERNS).each do |pattern, desc|
      return desc if line.matches?(pattern)
    end

    nil
  end

  private def check_handler_auth(lines : Array(String), route_line : Int32) : String?
    end_idx = [route_line + 15, lines.size - 1].min
    brace_depth = 0

    (route_line..end_idx).each do |idx|
      current = lines[idx]

      HANDLER_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      # Track braces from the route line itself, so a closure that opens and
      # closes there (`app.get("hello") { req in "Hello" }`) ends the walk
      # instead of reading the next route's body as this one's.
      brace_depth += current.count('{') - current.count('}')
      break if brace_depth <= 0
    end

    nil
  end
end
