require "../../../models/framework_tagger"
require "../../../models/endpoint"

class RubyAuthTagger < FrameworkTagger
  # Rails before_action patterns
  BEFORE_ACTION_PATTERNS = [
    {/before_action\s+:authenticate_user!/, "Devise authenticate_user!"},
    {/before_action\s+:authenticate_/, "Devise authentication"},
    {/before_action\s+:require_login/, "require_login"},
    {/before_action\s+:require_authentication/, "require_authentication"},
    {/before_action\s+:authorize/, "authorize"},
    {/before_action\s+:check_auth/, "check_auth"},
    {/before_action\s+:verify_authenticity_token/, "CSRF verify_authenticity_token"},
    {/before_action\s+:doorkeeper_authorize!/, "Doorkeeper OAuth authorize"},
    {/before_action\s+:authenticate_with_token/, "token authentication"},
  ]

  # Pundit / CanCanCan authorization in action body
  ACTION_AUTH_PATTERNS = [
    {/authorize\s+@?\w+/, "Pundit authorize"},
    {/authorize!\s*/, "CanCanCan authorize!"},
    {/load_and_authorize_resource/, "CanCanCan load_and_authorize_resource"},
  ]

  # Sinatra/Rack patterns
  SINATRA_AUTH_PATTERNS = [
    {/before\s+do.*auth/, "Sinatra before filter auth"},
    {/use\s+Rack::Auth/, "Rack::Auth middleware"},
    {/use\s+Warden/, "Warden middleware"},
    {/env\['warden'\]\.authenticate/, "Warden authenticate"},
    {/protected!/, "protected! helper"},
    {/halt\s+401/, "401 halt guard"},
  ]

  # Hanami patterns
  HANAMI_AUTH_PATTERNS = [
    {/before\s+:authenticate/, "Hanami authenticate"},
    {/before\s+:authorize/, "Hanami authorize"},
  ]

  # skip_before_action marks public overrides
  SKIP_PATTERNS = [
    /skip_before_action\s+:authenticate/,
    /skip_before_action\s+:require_login/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "ruby_auth"
  end

  def self.target_techs : Array(String)
    ["ruby_rails", "ruby_sinatra", "ruby_hanami"]
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

      # For Rails: find enclosing class, check before_action
      description = check_controller_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ruby_auth"))
        return
      end

      # Check action body for authorization calls
      description = check_action_body_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ruby_auth"))
        return
      end

      # Check Sinatra/Rack patterns in context
      description = check_sinatra_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ruby_auth"))
        return
      end
    end
  end

  private def check_controller_auth(lines : Array(String), action_line : Int32) : String?
    # Walk backwards to find the controller class and before_action declarations
    idx = action_line
    action_name = extract_action_name(lines, action_line)
    found_class = false

    while idx >= 0
      current = lines[idx].strip

      # Check for skip_before_action that applies to this action
      SKIP_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          # Check if it applies to this specific action via only: []
          if current.includes?("only:")
            if action_name && current.includes?(":#{action_name}")
              return nil # Explicitly skipped
            end
          else
            return nil # Broadly skipped
          end
        end
      end

      # Check for before_action with auth
      BEFORE_ACTION_PATTERNS.each do |pattern, desc|
        if current.matches?(pattern)
          # Check if it has only: restriction
          if current.includes?("only:")
            if action_name && current.includes?(":#{action_name}")
              return desc
            end
          elsif current.includes?("except:")
            if action_name && current.includes?(":#{action_name}")
              next # Excluded
            end
            return desc
          else
            return desc # Applies to all actions
          end
        end
      end

      # Check Hanami patterns
      HANAMI_AUTH_PATTERNS.each do |pattern, desc|
        if current.matches?(pattern)
          return desc
        end
      end

      if current.starts_with?("class ")
        found_class = true
        break
      end

      idx -= 1
    end

    nil
  end

  private def check_action_body_auth(lines : Array(String), action_line : Int32) : String?
    # Scan forward from the action definition for auth calls
    idx = action_line + 1
    end_idx = [action_line + 20, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx].strip
      # Stop at next method definition
      break if current.starts_with?("def ") && idx > action_line

      ACTION_AUTH_PATTERNS.each do |pattern, desc|
        if current.matches?(pattern)
          return desc
        end
      end

      idx += 1
    end

    nil
  end

  private def check_sinatra_auth(lines : Array(String), route_line : Int32) : String?
    # Check surrounding context for Sinatra auth patterns
    start_idx = [route_line - 15, 0].max

    (start_idx...route_line).each do |idx|
      current = lines[idx].strip

      SINATRA_AUTH_PATTERNS.each do |pattern, desc|
        if current.matches?(pattern)
          return desc
        end
      end
    end

    nil
  end

  private def extract_action_name(lines : Array(String), line_idx : Int32) : String?
    return nil if line_idx < 0 || line_idx >= lines.size
    line = lines[line_idx].strip
    match = line.match(/def\s+(\w+)/)
    match ? match[1] : nil
  end
end
