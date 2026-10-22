require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "crystal_auth", name: "Crystal Auth Tagger", desc: "Identifies Crystal framework authentication patterns (Kemal, Amber, Lucky)", order: 240)]
class CrystalAuthTagger < FrameworkTagger
  # Amber auth pipe patterns
  AMBER_AUTH_PATTERNS = [
    {/pipeline\s+:auth/, "Amber :auth pipeline"},
    {/plug\s+Authenticate/, "Amber Authenticate plug"},
    {/plug\s+\w*[Aa]uth\w*/, "Amber auth plug"},
  ]

  # Kemal file-level filters: they guard every route below them.
  KEMAL_FILTER_PATTERNS = [
    {/before_all.*do.*auth/i, "Kemal before_all auth filter"},
    {/basic_auth/, "Kemal basic_auth"},
  ]

  # Kemal checks that guard only the handler making them.
  KEMAL_HANDLER_PATTERNS = [
    {/env\.session\.string\s*\(\s*"user/, "Kemal session user check"},
    {/env\.get\s*\(\s*"auth/, "Kemal auth context"},
  ]

  # Lucky auth patterns
  LUCKY_AUTH_PATTERNS = [
    {/include Auth::RequireSignIn/, "Lucky Auth::RequireSignIn"},
    {/before require_sign_in/, "Lucky require_sign_in before action"},
    # A bare `current_user` reference (e.g. `UserSerializer.new(current_user)`
    # in a handler body) is not sign-in enforcement; it false-positived on
    # any action that merely reads the user. The real signals above
    # (RequireSignIn / require_sign_in) cover Lucky auth.
  ]

  # Lucky's opt-out of the sign-in `BrowserAction` requires: the action is
  # public, so nothing above it in the class may tag it.
  LUCKY_ALLOW_GUESTS = /include\s+Auth::AllowGuests\b/

  # Grip/Marten auth patterns
  GENERIC_FILTER_PATTERNS = [
    {/before_action.*auth/i, "Crystal before_action auth"},
  ]
  GENERIC_HANDLER_PATTERNS = [
    {/context\.session/, "Crystal session check"},
  ]

  # Read walking back from the route to its class/module: statements that
  # cover every route declared after them in that scope. A session read is
  # not one — it guards only the handler it sits in, and walking back to it
  # spread one route's check to every later route of the file.
  ENCLOSING_AUTH_PATTERNS = AMBER_AUTH_PATTERNS + KEMAL_FILTER_PATTERNS + LUCKY_AUTH_PATTERNS + GENERIC_FILTER_PATTERNS

  # Read inside the route's own block.
  HANDLER_AUTH_PATTERNS = KEMAL_FILTER_PATTERNS + KEMAL_HANDLER_PATTERNS + LUCKY_AUTH_PATTERNS +
                          GENERIC_FILTER_PATTERNS + GENERIC_HANDLER_PATTERNS

  def self.target_techs : Array(String)
    ["crystal_kemal", "crystal_amber", "crystal_lucky", "crystal_grip", "crystal_marten"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
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
      return if current.matches?(LUCKY_ALLOW_GUESTS)

      ENCLOSING_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      # Stop at module/class definition
      break if current.starts_with?("module ") || current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  # The route's own `do ... end`: the route line and the lines indented
  # under it.
  private def check_handler_auth(lines : Array(String), route_line : Int32) : String?
    indent = lines[route_line].size - lines[route_line].lstrip.size
    (route_line...lines.size).each do |idx|
      current = lines[idx].strip
      next if current.empty?
      break if idx > route_line && lines[idx].size - lines[idx].lstrip.size <= indent

      HANDLER_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    nil
  end
end
