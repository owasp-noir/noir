require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../minilexers/scala_lexer"

@[Noir::TaggerFor(key: "scala_auth", name: "Scala Auth Tagger", desc: "Identifies Play/Akka/Scalatra authentication patterns", order: 230)]
class ScalaAuthTagger < FrameworkTagger
  @lexer_cache = Hash(String, Tuple(Array(String), Array(String))).new
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

  private def scala_views(path : String) : Tuple(Array(String), Array(String))?
    if cached = @lexer_cache[path]?
      return cached
    end
    content = read_file(path)
    return unless content
    lexer = Noir::ScalaLexer.new(content)
    views = {lexer.code_lines, lexer.masked_lines}
    @lexer_cache[path] = views
    views
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      views = scala_views(path_info.path)
      next if views.nil?
      code_lines, masked_lines = views
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > code_lines.size
      line_idx = line_num - 1

      # Check route definition and surrounding context
      description = check_auth_patterns(code_lines, masked_lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "scala_auth"))
        return
      end

      # Check enclosing scope for auth directives (Akka)
      description = check_enclosing_auth(code_lines, masked_lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "scala_auth"))
        return
      end
    end

    check_handler(endpoint)
  end

  # A Play `conf/routes` row points at a controller action. The guard is the
  # action builder that action is written with (`def x = silhouette.SecuredAction
  # { ... }`), so read the action's own definition, not the routes line.
  private def check_handler(endpoint : Endpoint)
    handler = endpoint.handler || return
    path = handler.path || return
    line_num = handler.line || return
    views = scala_views(path)
    return if views.nil?
    code_lines, masked_lines = views
    return if line_num < 1 || line_num > code_lines.size

    if description = check_action_definition(code_lines, masked_lines, line_num - 1)
      endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "scala_auth"))
    end
  end

  # The `def` line and its body, down to the brace that closes the body or
  # the next `def`, whichever comes first. Never the lines above: they
  # belong to the previous action.
  private def check_action_definition(code_lines : Array(String), masked_lines : Array(String), def_idx : Int32) : String?
    end_idx = [def_idx + 10, code_lines.size - 1].min
    depth = 0
    opened = false
    (def_idx..end_idx).each do |i|
      current_code = code_lines[i]
      current_masked = masked_lines[i]
      break if i > def_idx && current_masked.matches?(/^\s*(?:(?:override|private|protected|final|inline)\s+)*def\s/)
      PLAY_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current_code.matches?(pattern)
      end
      depth += current_masked.count('{') - current_masked.count('}')
      opened ||= current_masked.includes?('{')
      break if opened && depth <= 0
    end

    nil
  end

  # The route's own block plus the few lines above it (annotations, a
  # wrapping action), never reaching into a neighbouring route's block.
  private def check_auth_patterns(code_lines : Array(String), masked_lines : Array(String), line_idx : Int32) : String?
    all_patterns = PLAY_AUTH_PATTERNS + SCALATRA_AUTH_PATTERNS

    # Upward, stopping at the end of the previous block.
    idx = line_idx - 1
    while idx >= 0 && idx >= line_idx - 5
      current_code = code_lines[idx]
      current_masked = masked_lines[idx]
      break if current_masked.strip.ends_with?('}')
      all_patterns.each do |pattern, desc|
        return desc if current_code.matches?(pattern)
      end
      idx -= 1
    end

    # Downward, through the brace that closes the route's block.
    end_idx = [line_idx + 10, code_lines.size - 1].min
    depth = 0
    opened = false
    (line_idx..end_idx).each do |i|
      current_code = code_lines[i]
      current_masked = masked_lines[i]
      all_patterns.each do |pattern, desc|
        return desc if current_code.matches?(pattern)
      end
      depth += current_masked.count('{') - current_masked.count('}')
      opened ||= current_masked.includes?('{')
      break if opened && depth <= 0
    end

    nil
  end

  private def check_enclosing_auth(code_lines : Array(String), masked_lines : Array(String), line_idx : Int32) : String?
    # Walk backwards for Akka HTTP auth directives wrapping this route
    # Only a line that opens a block still open at the route encloses it.
    # A balanced sibling (`authorize(x) { … }` in the object above) does
    # not: counting `<= 0` let it through once the route's own openers
    # were subtracted.
    idx = line_idx - 1
    balance = 0

    while idx >= 0 && idx >= line_idx - 20
      current_code = code_lines[idx]
      current_masked = masked_lines[idx]
      # Right to left, so `} ~ authenticateBasic(…) {` (closes a sibling,
      # opens the enclosing block) still reads as an opener.
      opens = false
      current_masked.reverse.each_char do |char|
        if char == '}'
          balance += 1
        elsif char == '{'
          balance -= 1
          opens = true if balance < 0
        end
      end

      if opens
        stripped = current_code.strip
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
