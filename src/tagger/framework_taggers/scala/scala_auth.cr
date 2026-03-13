require "../../../models/framework_tagger"
require "../../../models/endpoint"

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
    {/silhouette\.\w+\.SecuredAction/, "Play Silhouette SecuredAction"},
    {/silhouette\.\w+\.UserAwareAction/, "Play Silhouette UserAwareAction"},
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

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "scala_auth"
  end

  def self.target_techs : Array(String)
    ["scala_play", "scala_akka", "scala_scalatra", "java_play"]
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

  private def check_auth_patterns(lines : Array(String), line_idx : Int32) : String?
    start_idx = [line_idx - 5, 0].max
    end_idx = [line_idx + 10, lines.size - 1].min

    all_patterns = PLAY_AUTH_PATTERNS + SCALATRA_AUTH_PATTERNS
    (start_idx..end_idx).each do |idx|
      current = lines[idx]
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    nil
  end

  private def check_enclosing_auth(lines : Array(String), line_idx : Int32) : String?
    # Walk backwards for Akka HTTP auth directives wrapping this route
    idx = line_idx - 1
    brace_depth = 0

    while idx >= 0 && idx >= line_idx - 20
      current = lines[idx]
      stripped = current.strip

      brace_depth += current.count('}') - current.count('{')

      AKKA_AUTH_PATTERNS.each do |pattern, desc|
        return desc if stripped.matches?(pattern) && brace_depth <= 0
      end

      idx -= 1
    end

    nil
  end
end
