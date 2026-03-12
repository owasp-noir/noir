require "../../../models/framework_tagger"
require "../../../models/endpoint"

class ElixirAuthTagger < FrameworkTagger
  # Phoenix pipeline auth plugs
  PLUG_AUTH_PATTERNS = [
    {/plug\s+:require_authenticated_user/, "Phoenix require_authenticated_user plug"},
    {/plug\s+:authenticate/, "Phoenix authenticate plug"},
    {/plug\s+:require_auth/, "Phoenix require_auth plug"},
    {/plug\s+:ensure_authenticated/, "Phoenix ensure_authenticated plug"},
    {/plug\s+:fetch_current_user/, "Phoenix fetch_current_user plug"},
    {/plug\s+\w*[Aa]uth\w*/, "Phoenix auth plug"},
  ]

  # Plug-level auth (in router or controller)
  PLUG_MODULE_PATTERNS = [
    {/plug\s+\w+\.Auth/, "Phoenix Auth module plug"},
    {/plug\s+\w+\.RequireAuth/, "Phoenix RequireAuth module plug"},
    {/plug\s+\w+\.EnsureAuthenticated/, "Phoenix EnsureAuthenticated plug"},
    {/plug\s+Guardian\.Plug\.EnsureAuthenticated/, "Guardian EnsureAuthenticated"},
    {/plug\s+Guardian\.Plug\.VerifyHeader/, "Guardian VerifyHeader"},
    {/plug\s+Pow\.Plug\.RequireAuthenticated/, "Pow RequireAuthenticated"},
  ]

  # Action-level auth checks
  ACTION_AUTH_PATTERNS = [
    {/conn\.assigns\.\w*current_user/, "Phoenix current_user check"},
    {/Guardian\.Plug\.current_resource/, "Guardian current_resource"},
    {/Pow\.Plug\.current_user/, "Pow current_user"},
    {/get_session\s*\(\s*conn,\s*:user/, "Phoenix session user check"},
  ]

  # Pipeline references
  PIPELINE_AUTH_PATTERNS = [
    {/pipe_through\s+\[.*:authenticated/, "Phoenix :authenticated pipeline"},
    {/pipe_through\s+:authenticated/, "Phoenix :authenticated pipeline"},
    {/pipe_through\s+\[.*:auth/, "Phoenix :auth pipeline"},
    {/pipe_through\s+:auth/, "Phoenix :auth pipeline"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "elixir_auth"
    @auth_scopes = [] of {prefix: String, description: String}
  end

  def self.target_techs : Array(String)
    ["elixir_phoenix", "elixir_plug"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan routers for pipeline-scope auth
    @auth_scopes.clear
    pre_scan_router_pipelines

    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def pre_scan_router_pipelines
    files = get_files_by_prefix_and_extension(@base_path, ".ex")
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      next unless content.includes?("scope") && content.includes?("pipe_through")

      scan_router(content)
    end
  end

  private def scan_router(content : String)
    lines = content.split("\n")
    current_scope : String? = nil
    in_auth_scope = false

    lines.each do |line|
      stripped = line.strip

      # Track scope
      scope_match = stripped.match(/scope\s+["']([^"']+)["']/)
      if scope_match
        current_scope = scope_match[1]
        in_auth_scope = false
      end

      # Check for authenticated pipeline
      PIPELINE_AUTH_PATTERNS.each do |pattern, desc|
        if stripped.matches?(pattern) && current_scope
          @auth_scopes << {prefix: current_scope, description: "Protected by #{desc}"}
          in_auth_scope = true
        end
      end

      if stripped == "end"
        current_scope = nil
        in_auth_scope = false
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      line_idx = line_num - 1

      # Check controller-level plugs
      description = check_controller_plugs(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "elixir_auth"))
        return
      end

      # Check action body for auth checks
      description = check_action_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "elixir_auth"))
        return
      end
    end

    # Check router scope-level auth
    description = check_scope_auth(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "elixir_auth"))
    end
  end

  private def check_controller_plugs(lines : Array(String), action_line : Int32) : String?
    idx = action_line
    while idx >= 0
      current = lines[idx].strip

      all_patterns = PLUG_AUTH_PATTERNS + PLUG_MODULE_PATTERNS
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      break if current.starts_with?("defmodule ")
      idx -= 1
    end

    nil
  end

  private def check_action_auth(lines : Array(String), action_line : Int32) : String?
    idx = action_line + 1
    end_idx = [action_line + 15, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx].strip
      break if current.starts_with?("def ") || current.starts_with?("defp ")

      ACTION_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

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
