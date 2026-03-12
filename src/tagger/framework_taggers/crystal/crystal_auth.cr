require "../../../models/framework_tagger"
require "../../../models/endpoint"

class CrystalAuthTagger < FrameworkTagger
  # Amber auth pipe patterns
  AMBER_AUTH_PATTERNS = [
    {/pipeline\s+:auth/, "Amber :auth pipeline"},
    {/plug\s+Authenticate/, "Amber Authenticate plug"},
    {/plug\s+\w*[Aa]uth\w*/, "Amber auth plug"},
  ]

  # Kemal auth patterns
  KEMAL_AUTH_PATTERNS = [
    {/before_all.*do.*auth/i, "Kemal before_all auth filter"},
    {/env\.session\.string\s*\(\s*"user/, "Kemal session user check"},
    {/env\.get\s*\(\s*"auth/, "Kemal auth context"},
    {/basic_auth/, "Kemal basic_auth"},
  ]

  # Lucky auth patterns
  LUCKY_AUTH_PATTERNS = [
    {/include Auth::RequireSignIn/, "Lucky Auth::RequireSignIn"},
    {/include Auth::AllowGuests/, "Lucky Auth::AllowGuests"},
    {/before require_sign_in/, "Lucky require_sign_in before action"},
    {/current_user/, "Lucky current_user check"},
  ]

  # Grip/Marten auth patterns
  GENERIC_CRYSTAL_AUTH = [
    {/before_action.*auth/i, "Crystal before_action auth"},
    {/context\.session/, "Crystal session check"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "crystal_auth"
  end

  def self.target_techs : Array(String)
    ["crystal_kemal", "crystal_amber", "crystal_lucky", "crystal_grip", "crystal_marten"]
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

      # Check for auth patterns in enclosing scope
      description = check_enclosing_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "crystal_auth"))
        return
      end

      # Check route handler body
      description = check_handler_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "crystal_auth"))
        return
      end
    end
  end

  private def check_enclosing_auth(lines : Array(String), route_line : Int32) : String?
    idx = route_line
    while idx >= 0
      current = lines[idx].strip

      all_patterns = AMBER_AUTH_PATTERNS + KEMAL_AUTH_PATTERNS + LUCKY_AUTH_PATTERNS + GENERIC_CRYSTAL_AUTH
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      # Stop at module/class definition
      break if current.starts_with?("module ") || current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  private def check_handler_auth(lines : Array(String), route_line : Int32) : String?
    idx = route_line + 1
    end_idx = [route_line + 10, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx].strip

      all_patterns = KEMAL_AUTH_PATTERNS + LUCKY_AUTH_PATTERNS + GENERIC_CRYSTAL_AUTH
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx += 1
    end

    nil
  end
end
