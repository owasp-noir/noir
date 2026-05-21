require "../../../models/framework_tagger"
require "../../../models/endpoint"

class FastEndpointsAuthTagger < FrameworkTagger
  ALLOW_ANONYMOUS_PATTERN = /\bAllowAnonymous\s*\(/
  ROLES_PATTERN           = /\bRoles\s*\(/
  PERMISSIONS_PATTERN     = /\bPermissions\s*\(/
  POLICIES_PATTERN        = /\bPolicies\s*\(/
  POLICY_PATTERN          = /\bPolicy\s*\(/
  CLAIMS_PATTERN          = /\bClaims\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "fastendpoints_auth"
  end

  def self.target_techs : Array(String)
    ["cs_fastendpoints"]
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

      configure_block = extract_configure_block(content)
      next if configure_block.nil?

      if configure_block.matches?(ALLOW_ANONYMOUS_PATTERN)
        return
      end

      description = describe_guard(configure_block)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by FastEndpoints #{description}", "fastendpoints_auth"))
        return
      end
    end
  end

  private def extract_configure_block(content : String) : String?
    lines = content.lines
    lines.each_with_index do |line, index|
      next unless line.includes?("Configure") && line.includes?("(") && line.includes?(")")
      next unless line.includes?("override") || line.includes?("public") || line.includes?("protected")
      return capture_method_block(lines, index)
    end
    nil
  end

  private def capture_method_block(lines : Array(String), start_index : Int32) : String
    io = String::Builder.new
    brace = 0
    started = false
    index = start_index
    while index < lines.size
      line = lines[index]
      brace += line.count('{') - line.count('}')
      started ||= brace > 0 || line.includes?("{")
      io << line
      io << '\n'
      if started && brace <= 0 && line.includes?("}")
        break
      end
      index += 1
    end
    io.to_s
  end

  private def describe_guard(block : String) : String?
    return "Roles" if block.matches?(ROLES_PATTERN)
    return "Permissions" if block.matches?(PERMISSIONS_PATTERN)
    return "Policies" if block.matches?(POLICIES_PATTERN)
    return "Policy" if block.matches?(POLICY_PATTERN)
    return "Claims" if block.matches?(CLAIMS_PATTERN)
    nil
  end
end
