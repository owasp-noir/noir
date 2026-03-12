require "../../../models/framework_tagger"
require "../../../models/endpoint"

class SpringAuthTagger < FrameworkTagger
  ANNOTATION_PATTERNS = [
    /\@PreAuthorize\s*\(/,
    /\@Secured\s*\(/,
    /\@RolesAllowed\s*\(/,
  ]

  # Patterns for security config URL rules
  ANT_MATCHERS_AUTH = /\.(antMatchers|requestMatchers)\s*\(([^)]+)\)\s*\.\s*(authenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority)\s*\(/
  MVC_MATCHERS_AUTH = /\.(mvcMatchers)\s*\(([^)]+)\)\s*\.\s*(authenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "spring_auth"
    @security_rules = [] of {pattern: String, description: String}
  end

  def self.target_techs : Array(String)
    ["java_spring", "kotlin_spring"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Phase 1: Pre-scan security config files
    pre_scan_security_configs

    # Phase 2 & 3: Check each endpoint
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end

    endpoints
  end

  private def pre_scan_security_configs
    @security_rules.clear

    # Find Java and Kotlin security config files
    extensions = [".java", ".kt"]
    extensions.each do |ext|
      files = get_files_by_prefix_and_extension(@base_path, ext)
      files.each do |file|
        content = read_file(file)
        next if content.nil?
        next unless content.includes?("SecurityFilterChain") || content.includes?("HttpSecurity") || content.includes?("WebSecurityConfigurerAdapter")

        scan_security_config(content)
      end
    end
  end

  private def scan_security_config(content : String)
    lines = content.split("\n")
    lines.each do |line|
      [ANT_MATCHERS_AUTH, MVC_MATCHERS_AUTH].each do |pattern|
        match = line.match(pattern)
        if match
          url_pattern = match[2].gsub("\"", "").strip
          auth_type = match[3]
          @security_rules << {pattern: url_pattern, description: "Protected by Spring Security #{auth_type} via #{match[1]}(\"#{url_pattern}\")"}
        end
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    # Phase 2: Check annotations near code_paths
    contexts = read_source_context(endpoint, 15)
    contexts.each do |ctx|
      description = check_annotations(ctx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "spring_auth"))
        return
      end
    end

    # Phase 3: Match endpoint URL against security config rules
    description = check_security_config_rules(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "spring_auth"))
    end
  end

  private def check_annotations(ctx : SourceContext) : String?
    line = ctx.line
    return unless line

    # Walk backwards from endpoint line to find annotations
    # Note: `line` is 1-indexed (from PathInfo), context array is 0-indexed
    lines = ctx.context
    context_start = [line - 15, 0].max
    endpoint_idx = line - 1 - context_start

    idx = [endpoint_idx - 1, lines.size - 1].min
    while idx >= 0 && idx < lines.size
      current_line = lines[idx].strip
      # Skip empty lines but stop at method/class boundaries
      if current_line.empty?
        idx -= 1
        next
      end
      break if current_line.starts_with?("public ") || current_line.starts_with?("private ") || current_line.starts_with?("protected ")
      break if current_line.starts_with?("class ") || current_line.starts_with?("}")
      break if current_line.ends_with?("}")

      ANNOTATION_PATTERNS.each do |pattern|
        if current_line.matches?(pattern)
          annotation_name = current_line.split("(").first.strip
          return "Protected by Spring #{annotation_name}"
        end
      end

      idx -= 1
    end

    nil
  end

  private def check_security_config_rules(endpoint : Endpoint) : String?
    url = endpoint.url

    @security_rules.each do |rule|
      pattern = rule[:pattern]
      # Handle ant-style patterns
      if matches_ant_pattern?(url, pattern)
        return rule[:description]
      end
    end

    nil
  end

  private def matches_ant_pattern?(url : String, pattern : String) : Bool
    # Handle comma-separated patterns
    patterns = pattern.split(",").map(&.strip)

    patterns.any? do |p|
      # Convert ant pattern to regex
      regex_str = p.gsub("**", "DOUBLE_STAR")
        .gsub("*", "[^/]*")
        .gsub("DOUBLE_STAR", ".*")
      url.matches?(/^#{regex_str}/)
    end
  rescue
    false
  end
end
