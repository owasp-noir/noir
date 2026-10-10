require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/call_fold"
require "../../../miniparsers/elixir_callee_extractor"

@[Noir::TaggerFor(key: "elixir_auth", name: "Elixir Auth Tagger", desc: "Identifies Phoenix/Plug authentication patterns (plugs, Guardian, Pow)", order: 190)]
class ElixirAuthTagger < FrameworkTagger
  # Phoenix pipeline auth plugs
  PLUG_AUTH_PATTERNS = [
    {/plug\s+:require_authenticated_user/, "Phoenix require_authenticated_user plug"},
    {/plug\s+:authenticate/, "Phoenix authenticate plug"},
    {/plug\s+:require_auth/, "Phoenix require_auth plug"},
    {/plug\s+:ensure_authenticated/, "Phoenix ensure_authenticated plug"},
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

  # A `pipe_through` atom that names an auth pipeline by convention:
  # `:auth`, `:authenticated`, phx.gen.auth's `:require_authenticated_user`,
  # `:ensure_auth`. `:redirect_if_user_is_authenticated`, the guest-only
  # pipeline phx.gen.auth puts the login pages behind, is not one.
  AUTH_PIPELINE_ATOM = /\A(?:require_|ensure_)?auth\w*\z/

  # `live_session ..., on_mount: [{UserAuth, :ensure_authenticated}]` (1.7)
  # / `:require_authenticated` (1.8), not `:mount_current_user`.
  LIVE_SESSION_AUTH = /:((?:ensure|require)_authenticated\w*)/

  ALL_PLUG_PATTERNS = PLUG_AUTH_PATTERNS + PLUG_MODULE_PATTERNS

  # A plug that rejects an unauthenticated request, which is what makes a
  # pipeline an auth pipeline. Loading plugs (`Guardian.Plug.VerifyHeader`,
  # `LoadResource, allow_blank: true`, `:fetch_current_user`) and the
  # `Ueberauth` OAuth login flow let anonymous callers through.
  ENFORCING_PLUG = /plug\s+(?::require_\w+|:ensure_\w*auth\w*|:authenticate\w*|(?:\w+\.)*(?:EnsureAuthenticated|RequireAuthenticated|RequireAuth\w*)\b)/

  def initialize(options : Hash(String, YAML::Any))
    super
    # Router file -> per-line description of the auth pipeline covering it.
    @auth_lines = Hash(String, Array(String?)).new
  end

  def self.target_techs : Array(String)
    ["elixir_bandit", "elixir_phoenix", "elixir_plug"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan routers for pipeline-scope auth
    @auth_lines.clear
    pre_scan_router_pipelines

    super
  end

  private def pre_scan_router_pipelines
    files = collect_files_by_extension(".ex")
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      next unless content.includes?("pipe_through") || content.includes?("live_session")

      @auth_lines[file] = scan_router(content)
    end
  end

  # Which router lines sit inside a `do ... end` block that pipes through an
  # auth pipeline (or a `live_session` mounting an auth hook). Tracked by
  # block, not by scope prefix: phx.gen.auth puts its public, guest-only and
  # authenticated routes in three `scope "/"` blocks, so a prefix match spread
  # one block's auth over every route in the app.
  private def scan_router(content : String) : Array(String?)
    lines = content.split("\n")
    cut = lines.map { |l| Noir::ElixirCalleeExtractor.strip_comment(l).strip }
    # `pipe_through [` / `:browser,` / `:auth` / `]` is matched on the
    # folded view; string contents are blanked, the patterns are atoms.
    pipe_lines = Noir::CallFold.fold(lines) { |l| Noir::ElixirCalleeExtractor.strip_comment(l) }
    auth_pipelines = pipelines_with_auth_plugs(cut)

    covered = Array(String?).new(lines.size, nil)
    stack = [] of String?
    live_header = false
    live_auth : String? = nil

    cut.each_with_index do |line, index|
      pipe_line = pipe_lines[index].strip
      if pipe_line.starts_with?("pipe_through") && !stack.empty?
        if desc = pipe_through_auth(pipe_line, auth_pipelines)
          stack[-1] = desc
        end
      end

      if line.starts_with?("live_session")
        live_header = true
        live_auth = nil
      end
      if live_header && (m = line.match(LIVE_SESSION_AUTH))
        live_auth = "Phoenix live_session :#{m[1]} on_mount"
      end

      covered[index] = stack.compact.last?.try { |active| "Protected by #{active}" }

      if line.matches?(/(?:^|\s)do$/) || (line.ends_with?("->") && line.includes?("fn"))
        stack << (live_header ? live_auth : nil)
        live_header = false
      elsif line == "end" || line.starts_with?("end ")
        stack.pop?
      end
    end

    covered
  end

  # Pipelines whose own body plugs an enforcing auth check, so `pipe_through :api_v1`
  # counts when `pipeline :api_v1` plugs `Guardian.Plug.EnsureAuthenticated`.
  private def pipelines_with_auth_plugs(cut : Array(String)) : Set(String)
    names = Set(String).new
    current : String? = nil
    cut.each do |line|
      if m = line.match(/^pipeline\s+:(\w+)\s+do$/)
        current = m[1]
      elsif line == "end"
        current = nil
      elsif (name = current) && line.matches?(ENFORCING_PLUG)
        names << name
      end
    end
    names
  end

  private def pipe_through_auth(line : String, auth_pipelines : Set(String)) : String?
    line.scan(/:(\w+)/) do |m|
      atom = m[1]
      if auth_pipelines.includes?(atom) || atom.matches?(AUTH_PIPELINE_ATOM)
        return "Phoenix :#{atom} pipeline"
      end
    end
    nil
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

      # Check controller-level plugs. A Phoenix router only plugs inside
      # `pipeline` blocks, which apply through `pipe_through` alone, so
      # walking up from a route line would credit every route with
      # whatever any pipeline above it plugs.
      description = phoenix_router?(path_info.path) ? nil : check_controller_plugs(lines, line_idx)
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

      ALL_PLUG_PATTERNS.each do |pattern, desc|
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

  private def phoenix_router?(path : String) : Bool
    !!read_file(path).try(&.matches?(/\buse\s+(?:Phoenix\.Router\b|[\w.]+,\s*:router\b)/))
  end

  private def check_scope_auth(endpoint : Endpoint) : String?
    endpoint.details.code_paths.each do |path_info|
      next unless (covered = @auth_lines[path_info.path]?) && (line = path_info.line)
      next if line < 1 || line > covered.size
      if desc = covered[line - 1]
        return desc
      end
    end
    nil
  end
end
