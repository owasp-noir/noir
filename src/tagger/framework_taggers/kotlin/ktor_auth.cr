require "../../../models/framework_tagger"
require "../../../models/endpoint"

class KtorAuthTagger < FrameworkTagger
  # Ktor authenticate block patterns
  AUTHENTICATE_BLOCK_PATTERNS = [
    {/authenticate\s*\(/, "Ktor authenticate block"},
    {/authenticate\s*\(\s*"([^"]+)"/, "Ktor named authenticate"},
  ]

  # Ktor session/JWT/basic auth in route context
  ROUTE_AUTH_PATTERNS = [
    {/principal</, "Ktor principal extraction"},
    {/call\.principal/, "Ktor call.principal"},
    {/call\.authentication/, "Ktor call.authentication"},
    {/sessions\.get</, "Ktor session check"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "ktor_auth"
    @auth_scopes = [] of {prefix: String, description: String}
  end

  def self.target_techs : Array(String)
    ["kotlin_ktor"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan for authenticate {} blocks with route prefixes
    pre_scan_auth_blocks

    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def pre_scan_auth_blocks
    @auth_scopes.clear

    files = get_files_by_prefix_and_extension(@base_path, ".kt")
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      next unless content.includes?("authenticate")

      scan_auth_blocks(content)
    end
  end

  private def scan_auth_blocks(content : String)
    lines = content.split("\n")
    # Stack-based prefix tracking for nested route() blocks
    prefix_stack = [] of String

    lines.each do |line|
      stripped = line.strip

      # Track route() prefix nesting
      route_match = stripped.match(/route\s*\(\s*"([^"]+)"/)
      if route_match
        prefix_stack << route_match[1]
      end

      # Detect authenticate block (only record if route prefix is known)
      if !prefix_stack.empty?
        AUTHENTICATE_BLOCK_PATTERNS.each do |pattern, _desc|
          if stripped.matches?(pattern)
            auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
            auth_name = auth_match ? auth_match[1] : "default"
            prefix = normalize_prefix(prefix_stack)
            @auth_scopes << {
              prefix:      prefix,
              description: "Protected by Ktor authenticate(\"#{auth_name}\") block",
            }
          end
        end
      end

      # Pop prefix on closing brace (end of route block)
      if (stripped == "}" || stripped == "})") && !prefix_stack.empty?
        prefix_stack.pop
      end
    end
  end

  private def normalize_prefix(segments : Array(String)) : String
    joined = segments.join("")
    parts = joined.split("/").reject(&.empty?)
    parts.empty? ? "/" : "/" + parts.join("/")
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      line_idx = line_num - 1

      # Check for authenticate block wrapping this route
      description = check_enclosing_authenticate(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ktor_auth"))
        return
      end

      # Check route handler body for principal/session access
      description = check_route_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ktor_auth"))
        return
      end
    end

    # Check scope-level auth
    description = check_scope_auth(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "ktor_auth"))
    end
  end

  private def check_enclosing_authenticate(lines : Array(String), route_line : Int32) : String?
    # Walk backwards to find an enclosing authenticate {} block
    # 30-line window: Ktor authenticate blocks can wrap multiple route definitions
    idx = route_line - 1
    brace_depth = 0

    while idx >= 0 && idx >= route_line - 30
      current = lines[idx]
      stripped = current.strip

      # Check pattern BEFORE counting braces on this line
      # brace_depth <= 0 means we haven't left the enclosing scope (handles nested route blocks)
      AUTHENTICATE_BLOCK_PATTERNS.each do |pattern, _desc|
        if stripped.matches?(pattern) && brace_depth <= 0
          auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
          if auth_match
            return "Ktor authenticate(\"#{auth_match[1]}\") block"
          end
          return "Ktor authenticate block"
        end
      end

      brace_depth += current.count('}') - current.count('{')

      idx -= 1
    end

    nil
  end

  private def check_route_auth(lines : Array(String), route_line : Int32) : String?
    idx = route_line + 1
    end_idx = [route_line + 15, lines.size - 1].min
    brace_depth = 1 # Inside the route handler's opening {

    while idx <= end_idx
      current = lines[idx]
      stripped = current.strip

      ROUTE_AUTH_PATTERNS.each do |pattern, desc|
        return desc if stripped.matches?(pattern)
      end

      brace_depth += current.count('{') - current.count('}')
      break if brace_depth <= 0

      idx += 1
    end

    nil
  end

  private def check_scope_auth(endpoint : Endpoint) : String?
    url = endpoint.url
    @auth_scopes.each do |scope|
      return scope[:description] if url.starts_with?(scope[:prefix])
    end
    nil
  end
end
