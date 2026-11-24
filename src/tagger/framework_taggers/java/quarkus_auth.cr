require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./java_access"

@[Noir::TaggerFor(key: "quarkus_auth", name: "Quarkus Auth Tagger", desc: "Identifies Quarkus authentication annotations and HTTP permission policies", order: 255)]
class QuarkusAuthTagger < FrameworkTagger
  record PermissionRule, root : String, paths : Array(String), policy : String, methods : Array(String), name : String, file : String, shared : Bool, enabled : Bool
  # A config line noir does not read that may change who is admitted.
  record UnreadSetting, root : String, file : String, text : String
  record Decision, public_access : Bool, description : String, access : Array(Access::Clause)
  # The Keycloak policy enforcer settings of one properties file: on, it
  # refuses every path but the `enforcement-mode=DISABLED` ones. `primary`
  # marks the module's own `src/main/resources` file.
  record PolicyEnforcer, root : String, primary : Bool, enabled : Bool, disabled : Array(String)

  # Method annotations override the class. A restricting annotation wins over
  # `@PermitAll` on the same member. `@PermitAll` is public; the others guard.
  SECURITY_ANNOTATION = /@([\w.]*\.)?(Authenticated|DenyAll|PermitAll|RolesAllowed|PermissionsAllowed)\b/
  PERMISSION_KEY      = /\Aquarkus\.http\.auth\.permission\.([^.]+)\.(paths|policy|methods|shared|enabled)\z/
  # Build-time defaults for Jakarta REST endpoints without a security annotation.
  UNANNOTATED_KEY    = /\Aquarkus\.security\.(?:jaxrs\.deny-unannotated-endpoints|jaxrs\.default-roles-allowed|deny-unannotated-members)\z/
  PROFILED_KEY       = /\A%[^.]+\.quarkus\.(?:http\.auth|security|keycloak\.policy-enforcer)\./
  POLICY_KEY         = /\Aquarkus\.http\.auth\.policy\.([^.]+)\.(.+)\z/
  PERMISSION_CHECKER = /@(?:[\w.]*\.)?PermissionChecker\s*\(\s*(?:value\s*=\s*)?("(?:[^"\\]|\\.)*")?/
  ENFORCER_KEY       = /\Aquarkus\.keycloak\.policy-enforcer\.(?:(enable|enforcement-mode)|paths\.("[^"]*"|[^.]+)\.(paths?|enforcement-mode|methods\.[^.]+\.scopes-enforcement-mode))\z/

  @rules = [] of PermissionRule
  @enforcers = [] of PolicyEnforcer
  # The `roles-allowed` of each `{root, name}` role policy, nil when unset.
  @policies = Hash({String, String}, String?).new
  @checkers : Set(String)? = Set(String).new
  @unannotated = [] of UnreadSetting
  @profiled = [] of UnreadSetting
  @programmatic = [] of String

  def self.target_techs : Array(String)
    ["java_quarkus"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @rules = load_permissions
    @checkers = load_checkers
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    public_annotation = false
    guard : Decision? = nil

    read_source_context(endpoint).each do |ctx|
      decision = annotation_decision(ctx)
      next unless decision
      if decision.public_access
        public_annotation = true
      else
        guard = decision
        public_annotation = false
        break
      end
    end

    # HTTP permissions are checked before the annotations, and both apply
    # (Quarkus "Authorization of web endpoints", standard security annotations).
    if guard
      endpoint.add_tag(Tag.new("auth", guard.description, "quarkus_auth", requires: JavaAccess.signed_in(guard.access + config_layer(endpoint), guard.description)))
      return
    end

    # A `permit` HTTP permission also exempts its paths from the Keycloak
    # policy enforcer (Quarkus Keycloak Authorization guide).
    if permission = permission_policy(endpoint)
      policy, pattern = permission
      unless policy.downcase == "permit"
        description = "Protected by Quarkus permission policy #{policy} (#{pattern})"
        endpoint.add_tag(Tag.new("auth", description, "quarkus_auth", requires: JavaAccess.signed_in(config_layer(endpoint, public_annotation), description)))
      end
    elsif enforced?(endpoint)
      endpoint.add_tag(Tag.new("auth", "Protected by Quarkus Keycloak policy enforcer", "quarkus_auth"))
    end
    if public_annotation
      endpoint.add_tag(Tag.new("anonymous", "Quarkus @PermitAll admits anonymous callers", "quarkus_auth"))
    end
  end

  # A security annotation on the method replaces the class's (Quarkus
  # "Authorization of web endpoints": the method-level annotation has
  # priority). One member may carry only one kind of them, except repeated
  # `@PermissionsAllowed`, all of which apply.
  private def annotation_decision(ctx : SourceContext) : Decision?
    line = ctx.line
    return unless line

    lines = Noir::CComments.strip(ctx.full_content).split('\n', remove_empty: false)
    found = member_annotations(lines, line - 1, ctx.path)
    return pick_annotation(found) unless found.empty?

    class_found = class_annotation_lines(lines).compact_map { |idx| security_annotation(lines, idx, ctx.path) }
    return unless picked = pick_annotation(class_found)
    # The annotations are the file's first class's: with another class in
    # the file they may not be the endpoint's.
    return picked if picked.public_access || lines.count(&.matches?(/(?:^|\s)class\s+\w/)) < 2
    Decision.new(false, picked.description, [Access::Clause.unresolved("security annotations of the file's first class", "security annotations of the file's first class", ctx.path)])
  end

  private def member_annotations(lines : Array(String), endpoint_idx : Int32, path : String) : Array(Decision)
    found = [] of Decision
    return found unless 0 <= endpoint_idx < lines.size

    idx = endpoint_idx - 1
    while idx >= 0 && idx >= endpoint_idx - 15
      current = lines[idx].strip
      if current.empty?
        idx -= 1
        next
      end
      break if member_boundary?(current)
      if item = security_annotation(lines, idx, path)
        found << item
      end
      idx -= 1
    end

    below_indices(lines, endpoint_idx).each do |below|
      if item = security_annotation(lines, below, path)
        found << item
      end
    end
    found
  end

  # The indices of `annotation_lines_below`'s lines.
  private def below_indices(lines : Array(String), endpoint_idx : Int32) : Array(Int32)
    cursor = endpoint_idx
    annotation_lines_below(lines, endpoint_idx, "@").map do |text|
      cursor += 1
      while cursor < lines.size - 1 && lines[cursor].strip != text
        cursor += 1
      end
      cursor
    end
  end

  private def security_annotation(lines : Array(String), idx : Int32, path : String) : Decision?
    return unless match = lines[idx].strip.match(SECURITY_ANNOTATION)
    name = match[2]
    return Decision.new(true, "", [] of Access::Clause) if name == "PermitAll"
    access =
      if ann = JavaAccess.annotation_in(lines, idx, name)
        Access.clauses(JavaAccess.quarkus(ann, @checkers), ann.text, path, idx + 1)
      else
        [Access::Clause.unresolved(lines[idx].strip, lines[idx].strip, path, idx + 1)]
      end
    Decision.new(false, "Protected by Quarkus @#{name}", access)
  end

  # A restricting annotation wins over `@PermitAll`; the first one names
  # the tag, and every one at the level adds its clauses.
  private def pick_annotation(found : Array(Decision)) : Decision?
    guards = found.reject(&.public_access)
    return found.first? if guards.empty?
    Decision.new(false, guards.first.description, guards.flat_map(&.access))
  end

  private def member_boundary?(line : String) : Bool
    return true if line.starts_with?("public ") || line.starts_with?("private ") || line.starts_with?("protected ")
    return true if line.starts_with?("class ") || line.matches?(/(?:^|\s)class\s+\w/)
    return true if line.starts_with?('}') || line.ends_with?('}') || line.ends_with?(';')
    line.matches?(/(?:^|\s)fun\s/)
  end

  # The indices of the annotation lines stacked above the first class.
  private def class_annotation_lines(lines : Array(String)) : Array(Int32)
    lines.each_with_index do |raw, idx|
      stripped = raw.strip
      next unless stripped.matches?(/(?:^|\s)class\s+\w/)
      collected = [] of Int32
      cursor = idx - 1
      while cursor >= 0
        prev = lines[cursor].strip
        if prev.empty?
          cursor -= 1
          next
        end
        break unless prev.starts_with?('@')
        collected << cursor
        cursor -= 1
      end
      return collected
    end
    [] of Int32
  end

  # The permission names app `@PermissionChecker` methods decide; nil when
  # one names its permission with anything but a literal.
  private def load_checkers : Set(String)?
    @programmatic.clear
    names = Set(String).new
    unread = false
    {".java", ".kt"}.flat_map { |ext| collect_files_by_extension(ext) }.each do |file|
      next unless content = read_file(file)
      # `HttpSecurity` observers define path policies in code.
      @programmatic << file if content.includes?("HttpSecurity") && content.matches?(/@Observes\s+(?:[\w.]+\.)?HttpSecurity\b/)
      next unless content.includes?("PermissionChecker")
      Noir::CComments.strip(content).scan(PERMISSION_CHECKER) do |found|
        if literal = found[1]?
          names << literal[1...-1]
        else
          unread = true
        end
      end
    end
    names unless unread
  end

  # The HTTP permissions and the policy enforcer that apply to the endpoint,
  # and the settings noir does not read that may: a profile override (it
  # depends on the profile the app runs under), a code-defined policy, and
  # for an endpoint without a security annotation the Jakarta REST defaults.
  private def config_layer(endpoint : Endpoint, annotated : Bool = true) : Array(Access::Clause)
    clauses = [] of Access::Clause
    files = endpoint.details.code_paths.map(&.path)
    settings = annotated ? @profiled : @profiled + @unannotated
    settings.each do |setting|
      next unless files.any? { |file| Noir::PathScope.under_root?(file, setting.root) }
      clauses << Access::Clause.unresolved(setting.text, setting.text, setting.file)
    end
    @programmatic.each { |file| clauses << Access::Clause.unresolved("@Observes HttpSecurity", "@Observes HttpSecurity", file) }
    verb = endpoint.method.upcase
    matched = [] of {PermissionRule, String, Int32}
    @rules.each do |rule|
      next unless files.any? { |file| Noir::PathScope.under_root?(file, rule.root) }
      rule.paths.each do |pattern|
        next unless permission_matches?(endpoint.url, pattern)
        if rule.methods.empty? || rule.methods.includes?(verb)
          matched << {rule, normalize_permission_path(pattern), pattern.delete('*').size}
        else
          # Quarkus refuses the methods a matching permission does not list,
          # unless another permission admits them: not read here.
          key = "quarkus.http.auth.permission.#{rule.name}.methods"
          clauses << Access::Clause.unresolved("#{key}=#{rule.methods.join(',')}", key, rule.file)
        end
      end
    end
    permit = false
    if best = matched.max_of?(&.[2])
      winners = matched.select { |rule, _, score| score == best && !rule.shared }
      patterns = winners.map(&.[1]).uniq!
      permit = !winners.empty? && winners.all? { |rule, _, _| rule.policy.downcase == "permit" }
      matched.each do |rule, _, score|
        source = "quarkus.http.auth.permission.#{rule.name}.policy=#{rule.policy}"
        if !rule.enabled && (rule.shared || score == best)
          # Off in config, and turned back on by a system property at run time.
          key = "quarkus.http.auth.permission.#{rule.name}.enabled=false"
          clauses << Access::Clause.unresolved(key, key, rule.file)
        elsif rule.shared || (score == best && patterns.size == 1)
          # All permissions of the most specific path apply, and every
          # shared one too.
          cnf = rule.policy.empty? ? [[Access::Atom.new(:unresolved, source)]] : JavaAccess.quarkus_policy(rule.policy, @policies[{rule.root, rule.policy}]?, @policies.has_key?({rule.root, rule.policy}))
          clauses.concat(Access.clauses(cnf, source, rule.file))
        elsif score == best
          # Two paths of equal length: noir's score does not say which one
          # Quarkus finds more specific.
          clauses << Access::Clause.unresolved(source, source, rule.file)
        end
      end
    end
    if !permit && enforced?(endpoint)
      source = "Quarkus Keycloak policy enforcer"
      clauses << Access::Clause.new([Access::Atom.new(:authenticated)], source)
      clauses << Access::Clause.unresolved(source, source)
    end
    # Two permissions of one policy require it once.
    clauses.uniq(&.any_of)
  end

  private def load_permissions : Array(PermissionRule)
    rules = [] of PermissionRule
    @enforcers.clear
    @policies.clear
    @unannotated.clear
    @profiled.clear
    get_files_by_basename("application.properties").each do |path|
      next unless @base_paths.any? { |base| Noir::PathScope.under_root?(path, base) }
      content = read_file(path)
      next if content.nil?

      grouped = Hash(String, Hash(String, String)).new { |hash, key| hash[key] = Hash(String, String).new }
      enforcer = Hash(String, String).new
      enforcer_paths = Hash(String, Hash(String, String)).new { |hash, key| hash[key] = Hash(String, String).new }
      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#') || stripped.starts_with?('!')
        separator = stripped.index(/[=:]/)
        next unless separator
        key = stripped[...separator].strip
        value = stripped[(separator + 1)..].strip
        if key.matches?(PROFILED_KEY)
          @profiled << UnreadSetting.new(config_root(path), path, "#{key}=#{value}")
        elsif key.matches?(UNANNOTATED_KEY)
          @unannotated << UnreadSetting.new(config_root(path), path, "#{key}=#{value}")
        elsif match = key.match(PERMISSION_KEY)
          grouped[match[1]][match[2]] = value
        elsif match = key.match(POLICY_KEY)
          policy = {config_root(path), match[1]}
          if match[2] == "roles-allowed"
            @policies[policy] = value
          else
            @policies[policy] ||= nil
          end
        elsif match = key.match(ENFORCER_KEY)
          if setting = match[1]?
            enforcer[setting] = value
          else
            enforcer_paths[match[2]][match[3]] = value
          end
        end
      end

      root = config_root(path)
      unless enforcer.empty? && enforcer_paths.empty?
        enabled = enforcer["enable"]?.try(&.downcase) == "true" && enforcer.fetch("enforcement-mode", "ENFORCING").upcase == "ENFORCING"
        # ponytail: a path with any method DISABLED counts as disabled for
        # every method; a missed guard is better than an invented one.
        disabled = enforcer_paths.values.select { |fields| fields.any? { |key, value| key.ends_with?("enforcement-mode") && value.upcase == "DISABLED" } }
        paths = disabled.flat_map { |fields| "#{fields["path"]?},#{fields["paths"]?}".split(',').map(&.strip).reject(&.empty?) }
        @enforcers << PolicyEnforcer.new(root, root != File.dirname(Noir::PathScope.expand(path)), enabled, paths)
      end
      grouped.each do |name, fields|
        paths = fields["paths"]?.to_s.split(',').map(&.strip).reject(&.empty?)
        next if paths.empty?
        methods = fields["methods"]?.to_s.split(',').map(&.strip.upcase).reject(&.empty?)
        rules << PermissionRule.new(root, paths, fields["policy"]?.to_s.strip, methods, name, path, fields["shared"]?.try(&.downcase) == "true", fields["enabled"]?.try(&.downcase) != "false")
      end
    end
    rules
  end

  # `src/main/resources/application.properties` belongs to the module above
  # `src/main`. A properties file anywhere else scopes to its own directory.
  private def config_root(path : String) : String
    dir = File.dirname(Noir::PathScope.expand(path))
    return dir.rchop("/src/main/resources") if dir.ends_with?("/src/main/resources")
    dir
  end

  # The policy and pattern of the most specific HTTP permission for the endpoint.
  private def permission_policy(endpoint : Endpoint) : {String, String}?
    files = endpoint.details.code_paths.map(&.path)
    return if files.empty?

    best_score = -1
    best_policy = ""
    best_pattern = ""
    verb = endpoint.method.upcase

    @rules.each do |rule|
      next unless files.any? { |file| Noir::PathScope.under_root?(file, rule.root) }
      next unless rule.methods.empty? || rule.methods.includes?(verb)
      rule.paths.each do |pattern|
        next unless permission_matches?(endpoint.url, pattern)
        score = pattern.delete('*').size
        permit = rule.policy.downcase == "permit"
        best_permit = best_policy.downcase == "permit"
        if score > best_score || (score == best_score && best_permit && !permit)
          best_score = score
          best_policy = rule.policy
          best_pattern = pattern.strip
        end
      end
    end

    return if best_score < 0 || best_policy.empty?
    {best_policy, best_pattern}
  end

  # The nearest enforcer settings decide for a module: the deepest root,
  # and the module's own `src/main/resources` file over a stray one beside
  # it. A DISABLED `/x/*` is read as covering `/x` too: the Keycloak docs
  # leave that open, and a missed guard is better than an invented one.
  private def enforced?(endpoint : Endpoint) : Bool
    files = endpoint.details.code_paths.map(&.path)
    enforcer = @enforcers.select { |item| files.any? { |file| Noir::PathScope.under_root?(file, item.root) } }
      .max_by? { |item| {item.root.size, item.primary ? 1 : 0} }
    return false unless enforcer && enforcer.enabled
    url = normalize_permission_path(endpoint.url)
    enforcer.disabled.none? do |pattern|
      permission_matches?(url, pattern) || (pattern.ends_with?("/*") && url == normalize_permission_path(pattern.rchop("/*")))
    end
  end

  # A trailing `*` matches every sub-path (`/tokens/*` covers `/tokens/mine`).
  # Any other `*` is one path segment. The longest literal path wins.
  private def permission_matches?(url : String, pattern : String) : Bool
    url = normalize_permission_path(url)
    pattern = normalize_permission_path(pattern)
    if pattern.ends_with?("/*")
      url.starts_with?(pattern.rchop('*'))
    elsif pattern.includes?('*')
      body = pattern.split('*').map { |part| Regex.escape(part) }.join("[^/]*")
      url.matches?(Regex.new("\\A#{body}\\z"))
    else
      url == pattern
    end
  end

  private def normalize_permission_path(path : String) : String
    value = path.strip
    value = "/#{value}" unless value.starts_with?('/')
    value.size > 1 ? value.rchop('/') : value
  end
end
