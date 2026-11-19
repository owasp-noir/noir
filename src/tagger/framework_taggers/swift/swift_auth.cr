require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../minilexers/swift_lexer"

@[Noir::TaggerFor(key: "swift_auth", name: "Swift Auth Tagger", desc: "Identifies Vapor/Kitura/Hummingbird authentication patterns", order: 220)]
class SwiftAuthTagger < FrameworkTagger
  # `.group(` / `.grouped(` followed by any earlier arguments, so a pattern
  # after it matches at the start of ANY argument:
  # `app.grouped(UserToken.authenticator(), User.guardMiddleware())` is
  # guarded by its second one. `.group(...) { name in` is the closure form.
  GROUPED_ARG = /\.group(?:ed)?\s*\((?:[^(),]*(?:\([^()]*\)[^(),]*)?,\s*)*\s*/.source

  ROUTE_RECEIVER = /^(\$0|\w+)\.(?:get|post|put|delete|patch|on|group(?:ed)?)\b/

  # Vapor middleware patterns
  VAPOR_MIDDLEWARE_PATTERNS = [
    {/#{GROUPED_ARG}\w*[Aa]uth\w*/, "Vapor auth middleware group"},
    {/#{GROUPED_ARG}User\.authenticator\(\)/, "Vapor User.authenticator()"},
    {/#{GROUPED_ARG}Token\.authenticator\(\)/, "Vapor Token.authenticator()"},
    {/#{GROUPED_ARG}User\.guardMiddleware\(\)/, "Vapor User.guardMiddleware()"},
    {/#{GROUPED_ARG}\w+\.guardMiddleware\(\)/, "Vapor guardMiddleware"},
    # Sends an unauthenticated caller to the login page instead of a 401.
    {/#{GROUPED_ARG}\w+\.redirectMiddleware\s*\(/, "Vapor redirectMiddleware"},
    # After the guardMiddleware patterns so
    # `grouped(UserToken.authenticator(), User.guardMiddleware())` keeps the
    # guard description. `UserToken` has no `[Aa]uth` and is neither `User.`
    # nor `Token.`.
    {/#{GROUPED_ARG}UserToken\.authenticator\(\)/, "Vapor UserToken.authenticator()"},
    {/#{GROUPED_ARG}BearerAuthenticator/, "Vapor BearerAuthenticator"},
    {/#{GROUPED_ARG}BasicAuthenticator/, "Vapor BasicAuthenticator"},
    {/#{GROUPED_ARG}SessionAuthenticator/, "Vapor SessionAuthenticator"},
  ]

  # Calls that throw 401 when the request is unauthenticated.
  REQUIRE_AUTH_PATTERNS = [
    {/req\.auth\.require\s*\(/, "Vapor req.auth.require"},
    {/request\.auth\.require\s*\(/, "Vapor request.auth.require"},
    {/\bcontext\.requireIdentity\s*\(/, "Hummingbird requireIdentity"},
  ]

  # Auth requirement in route handler
  HANDLER_AUTH_PATTERNS = REQUIRE_AUTH_PATTERNS + [
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
      content = read_file(path_info.path)
      next if content.nil?
      lines = content.lines
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError, and
      # line 0 would otherwise scan the wrong region via lines[-1].
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      lexer = Noir::SwiftLexer.for(content)
      masked_lines = lexer.masked_lines

      # Check for auth middleware group wrapping this route
      description = check_middleware_group(lines, masked_lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "swift_auth"))
        return
      end

      # Check route handler body for auth requirements
      description = check_handler_auth(lines, masked_lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "swift_auth"))
        return
      end
    end
  end

  private def check_middleware_group(lines : Array(String), masked_lines : Array(String), route_line : Int32) : String?
    return if route_line < 0 || route_line >= lines.size

    # The receiver of the route (`protected` in `protected.get(...)`, `$0` in
    # a `.group(...) { $0.get(...) }` closure).
    return unless receiver = masked_lines[route_line].strip.match(ROUTE_RECEIVER).try(&.[1])

    # The binding may sit anywhere in this function (`let x = app.grouped(...)`
    # or an enclosing `group(...) { x in`, nested any depth). Stop at the
    # enclosing func/type so a same-named receiver in the previous function
    # is not this route's guard.
    depth = 0
    idx = route_line - 1
    while idx >= 0
      masked_stripped = masked_lines[idx].strip
      break if function_boundary?(masked_stripped)

      depth += masked_stripped.count('}') - masked_stripped.count('{')
      if depth < 0
        depth = 0
        # A closure enclosing the route. Only a group closure whose parameter
        # is the receiver puts its middleware in front of the route; then the
        # group's own receiver is what the next enclosing closure must bind.
        if (open = masked_stripped.match(/\.group(?:ed)?\s*\(.*\{\s*(?:(\w+)\s+in\b)?/)) && (open[1]? || "$0") == receiver
          if description = middleware_description(lines[idx])
            return description
          end
          return unless receiver = masked_stripped.match(ROUTE_RECEIVER).try(&.[1])
        end
      elsif binds_receiver?(masked_stripped, receiver)
        return middleware_description(lines[idx])
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

  private def check_handler_auth(lines : Array(String), masked_lines : Array(String), route_line : Int32) : String?
    end_idx = [route_line + 15, lines.size - 1].min
    brace_depth = 0

    (route_line..end_idx).each do |idx|
      current_masked = masked_lines[idx]

      HANDLER_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current_masked.matches?(pattern)
      end

      # Track braces from the route line itself on masked lines, so a closure that opens and
      # closes there (`app.get("hello") { req in "Hello" }`) ends the walk
      # instead of reading the next route's body as this one's, and strings with braces
      # do not terminate early.
      brace_depth += current_masked.count('{') - current_masked.count('}')
      break if brace_depth <= 0
    end

    check_named_handler(masked_lines, route_line)
  end

  # `use: self.current` / `use: current`: the handler method of this file.
  private def check_named_handler(masked_lines : Array(String), route_line : Int32) : String?
    return unless m = masked_lines[route_line].match(/\buse:\s*(?:self\.)?(\w+)\s*\)/)
    head = /\bfunc\s+#{Regex.escape(m[1])}\s*[(<]/
    return unless start = masked_lines.index(&.matches?(head))
    depth = 0
    masked_lines[start, 80].each do |line|
      REQUIRE_AUTH_PATTERNS.each do |pattern, desc|
        return desc if line.matches?(pattern)
      end
      depth += line.count('{') - line.count('}')
      break if depth <= 0 && line.includes?('}')
    end
    nil
  end
end
