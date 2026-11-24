require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"
require "./aspnet_access"

@[Noir::TaggerFor(key: "fastendpoints_auth", name: "FastEndpoints Auth Tagger", desc: "Identifies FastEndpoints authentication patterns (Roles, Permissions, Policies)", order: 180)]
class FastEndpointsAuthTagger < FrameworkTagger
  ALLOW_ANONYMOUS_PATTERN = /\bAllowAnonymous\s*\(/
  ROLES_PATTERN           = /\bRoles\s*\(/
  PERMISSIONS_PATTERN     = /\bPermissions\s*\(/
  POLICIES_PATTERN        = /\bPolicies\s*\(/
  POLICY_PATTERN          = /\bPolicy\s*\(/
  CLAIMS_PATTERN          = /\bClaims\s*\(/

  def self.target_techs : Array(String)
    ["cs_fastendpoints"]
  end

  @default_policy : String? = nil

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @default_policy = nil
    collect_files_by_extension(".cs").each do |path|
      content = read_file(path) || next
      next unless content.includes?("DefaultPolicy")
      @default_policy ||= AspnetAccess.default_policy_assignment(Noir::CComments.strip(content))
    end
    super
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

      # FastEndpoints endpoints are secure by default: without
      # `AllowAnonymous()` they require an authenticated user.
      description = "Protected by FastEndpoints #{describe_guard(configure_block) || "default authorization (no AllowAnonymous)"}"
      requires = Access.clauses(AspnetAccess.fastendpoints(configure_block, AspnetAccess.default_policy(@default_policy)), description, path_info.path)
      endpoint.add_tag(Tag.new("auth", description, "fastendpoints_auth", requires: requires))
      return
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
