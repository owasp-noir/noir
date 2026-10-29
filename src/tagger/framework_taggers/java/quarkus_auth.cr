require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "quarkus_auth", name: "Quarkus Auth Tagger", desc: "Identifies Quarkus authentication annotations and HTTP permission policies", order: 255)]
class QuarkusAuthTagger < FrameworkTagger
  record PermissionRule, root : String, paths : Array(String), policy : String, methods : Array(String)

  # Method annotations override the class. A restricting annotation wins over
  # `@PermitAll` on the same member. `@PermitAll` is public; the others guard.
  SECURITY_ANNOTATION = /@([\w.]*\.)?(Authenticated|DenyAll|PermitAll|RolesAllowed|PermissionsAllowed)\b/
  PERMISSION_KEY      = /\Aquarkus\.http\.auth\.permission\.([^.]+)\.(paths|policy|methods)\z/

  @rules = [] of PermissionRule

  def self.target_techs : Array(String)
    ["java_quarkus"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @rules = load_permissions
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    public_annotation = false
    guard : String? = nil

    read_source_context(endpoint).each do |ctx|
      decision = annotation_decision(ctx)
      next unless decision
      if decision[:public_access]
        public_annotation = true
      else
        guard = decision[:description]
        public_annotation = false
        break
      end
    end

    if guard
      endpoint.add_tag(Tag.new("auth", guard, "quarkus_auth"))
      return
    end

    if description = permission_description(endpoint)
      endpoint.add_tag(Tag.new("auth", description, "quarkus_auth"))
    end
    if public_annotation
      endpoint.add_tag(Tag.new("anonymous", "Quarkus @PermitAll admits anonymous callers", "quarkus_auth"))
    end
  end

  private def annotation_decision(ctx : SourceContext) : NamedTuple(public_access: Bool, description: String)?
    line = ctx.line
    return unless line

    lines = Noir::CComments.strip(ctx.full_content).split('\n', remove_empty: false)
    found = member_annotations(lines, line - 1)
    return pick_annotation(found) unless found.empty?

    class_lines = class_annotation_lines(lines)
    class_found = [] of NamedTuple(public_access: Bool, description: String)
    class_lines.each do |raw|
      item = security_annotation(raw)
      class_found << item if item
    end
    pick_annotation(class_found)
  end

  private def member_annotations(lines : Array(String), endpoint_idx : Int32) : Array(NamedTuple(public_access: Bool, description: String))
    found = [] of NamedTuple(public_access: Bool, description: String)
    return found unless 0 <= endpoint_idx < lines.size

    idx = endpoint_idx - 1
    while idx >= 0 && idx >= endpoint_idx - 15
      current = lines[idx].strip
      if current.empty?
        idx -= 1
        next
      end
      break if member_boundary?(current)
      if item = security_annotation(current)
        found << item
      end
      idx -= 1
    end

    annotation_lines_below(lines, endpoint_idx, "@").each do |below|
      if item = security_annotation(below)
        found << item
      end
    end
    found
  end

  private def security_annotation(line : String) : NamedTuple(public_access: Bool, description: String)?
    return unless match = line.match(SECURITY_ANNOTATION)
    name = match[2]
    if name == "PermitAll"
      {public_access: true, description: ""}
    else
      {public_access: false, description: "Protected by Quarkus @#{name}"}
    end
  end

  private def pick_annotation(found : Array(NamedTuple(public_access: Bool, description: String))) : NamedTuple(public_access: Bool, description: String)?
    found.find { |item| !item[:public_access] } || found.first?
  end

  private def member_boundary?(line : String) : Bool
    return true if line.starts_with?("public ") || line.starts_with?("private ") || line.starts_with?("protected ")
    return true if line.starts_with?("class ") || line.matches?(/(?:^|\s)class\s+\w/)
    return true if line.starts_with?('}') || line.ends_with?('}') || line.ends_with?(';')
    line.matches?(/(?:^|\s)fun\s/)
  end

  # Annotations stacked immediately above the class declaration.
  private def class_annotation_lines(lines : Array(String)) : Array(String)
    lines.each_with_index do |raw, idx|
      stripped = raw.strip
      next unless stripped.matches?(/(?:^|\s)class\s+\w/)
      collected = [] of String
      cursor = idx - 1
      while cursor >= 0
        prev = lines[cursor].strip
        if prev.empty?
          cursor -= 1
          next
        end
        break unless prev.starts_with?('@')
        collected << prev
        cursor -= 1
      end
      return collected
    end
    [] of String
  end

  private def load_permissions : Array(PermissionRule)
    rules = [] of PermissionRule
    get_files_by_basename("application.properties").each do |path|
      next unless @base_paths.any? { |base| Noir::PathScope.under_root?(path, base) }
      content = read_file(path)
      next if content.nil?

      grouped = Hash(String, Hash(String, String)).new { |hash, key| hash[key] = Hash(String, String).new }
      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#') || stripped.starts_with?('!')
        separator = stripped.index(/[=:]/)
        next unless separator
        key = stripped[...separator].strip
        value = stripped[(separator + 1)..].strip
        next unless match = key.match(PERMISSION_KEY)
        grouped[match[1]][match[2]] = value
      end

      root = config_root(path)
      grouped.each_value do |fields|
        paths = fields["paths"]?.to_s.split(',').map(&.strip).reject(&.empty?)
        next if paths.empty?
        methods = fields["methods"]?.to_s.split(',').map(&.strip.upcase).reject(&.empty?)
        rules << PermissionRule.new(root, paths, fields["policy"]?.to_s.strip, methods)
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

  private def permission_description(endpoint : Endpoint) : String?
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

    return if best_score < 0 || best_policy.empty? || best_policy.downcase == "permit"
    "Protected by Quarkus permission policy #{best_policy} (#{best_pattern})"
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
