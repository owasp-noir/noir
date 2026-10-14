require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "scala_auth", name: "Scala Auth Tagger", desc: "Identifies Play/Akka/Scalatra authentication patterns", order: 230)]
class ScalaAuthTagger < FrameworkTagger
  # Play Framework auth patterns
  PLAY_AUTH_PATTERNS = [
    {/Authenticated\s*[\{\(]/, "Play Authenticated action"},
    {/AuthenticatedAction/, "Play AuthenticatedAction"},
    {/WithAuthentication/, "Play WithAuthentication"},
    {/Security\.Authenticated/, "Play Security.Authenticated"},
    {/deadbolt/, "Play Deadbolt authorization"},
    {/SubjectPresent/, "Play Deadbolt SubjectPresent"},
    {/Restrict\s*\(/, "Play Deadbolt Restrict"},
    {/Dynamic\s*\(/, "Play Deadbolt Dynamic"},
    {/silhouette\.SecuredAction/, "Play Silhouette SecuredAction"},
    {/silhouette\.UserAwareAction/, "Play Silhouette UserAwareAction"},
  ]

  # Akka HTTP auth directives
  AKKA_AUTH_PATTERNS = [
    {/authenticateBasic\s*\(/, "Akka HTTP authenticateBasic"},
    {/authenticateOAuth2\s*\(/, "Akka HTTP authenticateOAuth2"},
    {/authorize\s*\(/, "Akka HTTP authorize directive"},
    {/authenticateOrRejectWithChallenge/, "Akka HTTP authenticateOrRejectWithChallenge"},
    {/extractCredentials/, "Akka HTTP extractCredentials"},
  ]

  # Scalatra auth patterns
  SCALATRA_AUTH_PATTERNS = [
    {/basicAuth\s*\{/, "Scalatra basicAuth"},
    {/scentry/, "Scalatra Scentry auth"},
    {/isAuthenticated/, "Scalatra isAuthenticated check"},
    {/userOption/, "Scalatra userOption check"},
  ]

  def self.target_techs : Array(String)
    ["scala_play", "scala_akka", "scala_scalatra", "java_play"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      # Check route definition and surrounding context
      description = check_auth_patterns(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "scala_auth"))
        return
      end

      # Check enclosing scope for auth directives (Akka)
      description = check_enclosing_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "scala_auth"))
        return
      end
    end
  end

  # The route's own block plus the few lines above it (annotations, a
  # wrapping action), never reaching into a neighbouring route's block.
  private def check_auth_patterns(lines : Array(String), line_idx : Int32) : String?
    all_patterns = PLAY_AUTH_PATTERNS + SCALATRA_AUTH_PATTERNS

    # Upward, stopping at the end of the previous block.
    idx = line_idx - 1
    while idx >= 0 && idx >= line_idx - 5
      current = lines[idx]
      break if current.strip.ends_with?('}')
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
      idx -= 1
    end

    # Downward, through the brace that closes the route's block.
    end_idx = [line_idx + 10, lines.size - 1].min
    depth = 0
    opened = false
    (line_idx..end_idx).each do |i|
      current = lines[i]
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
      depth += current.count('{') - current.count('}')
      opened ||= current.includes?('{')
      break if opened && depth <= 0
    end

    nil
  end

  private def check_enclosing_auth(lines : Array(String), line_idx : Int32) : String?
    # Walk backwards for Akka HTTP auth directives wrapping this route
    # Only a line that opens a block still open at the route encloses it.
    # A balanced sibling (`authorize(x) { … }` in the object above) does
    # not: counting `<= 0` let it through once the route's own openers
    # were subtracted.
    idx = line_idx - 1
    balance = 0

    while idx >= 0 && idx >= line_idx - 20
      current = lines[idx]
      balance += current.count('}') - current.count('{')

      if balance < 0
        stripped = current.strip
        AKKA_AUTH_PATTERNS.each do |pattern, desc|
          return desc if stripped.matches?(pattern)
        end
        balance = 0
      end

      idx -= 1
    end

    nil
  end
end
