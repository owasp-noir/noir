require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/call_fold"
require "../../../miniparsers/elixir_callee_extractor"
require "./elixir_plug_judge"

@[Noir::TaggerFor(key: "elixir_auth", name: "Elixir Auth Tagger", desc: "Identifies Phoenix/Plug authentication patterns (plugs, Guardian, Pow)", order: 190)]
class ElixirAuthTagger < FrameworkTagger
  # A `pipe_through` atom that names an auth pipeline by convention:
  # `:auth`, `:authenticated`, phx.gen.auth's `:require_authenticated_user`,
  # `:ensure_auth`. `:redirect_if_user_is_authenticated`, the guest-only
  # pipeline phx.gen.auth puts the login pages behind, is not one.
  AUTH_PIPELINE_ATOM = /\A(?:require_|ensure_)?auth\w*\z/

  # `live_session ..., on_mount: [{UserAuth, :ensure_authenticated}]` (1.7)
  # / `:require_authenticated` (1.8), not `:mount_current_user`.
  LIVE_SESSION_AUTH = /:((?:ensure|require)_authenticated\w*)/

  # A plug that rejects an unauthenticated request, which is what makes a
  # pipeline an auth pipeline. Loading plugs (`Guardian.Plug.VerifyHeader`,
  # `LoadResource, allow_blank: true`, `:fetch_current_user`) and the
  # `Ueberauth` OAuth login flow let anonymous callers through.
  # Only the fallback for plugs whose definition is not in the tree
  # (library plugs); an in-tree plug is judged by `Noir::ElixirPlugJudge`.
  ENFORCING_PLUG = /plug\s*\(?\s*(?::require_\w+|:ensure_\w*auth\w*|:authenticate\w*|:basic_auth\b|(?:\w+\.)*(?:EnsureAuthenticated|RequireAuthenticated|RequireAuth\w*|BasicAuth)\b)/

  # The plugged module or function atom, and its `when` clause if any.
  PLUG_STATEMENT = /\Aplug\s*\(?\s*(:\w+[!?]?|[A-Z][\w.]*)/
  PLUG_WHEN      = /\bwhen\s+(not\s+)?\(?\s*action\s+(not\s+)?in\s+(.+)\z/m

  def initialize(options : Hash(String, YAML::Any))
    super
    # Router file -> per-line description of the auth pipeline covering it.
    @auth_lines = Hash(String, Array(String?)).new
    @judge = nil.as(Noir::ElixirPlugJudge?)
  end

  private def judge : Noir::ElixirPlugJudge
    @judge ||= Noir::ElixirPlugJudge.new(collect_files_by_extension(".ex"), ->(path : String) { read_file_lines(path) })
  end

  # A plug reference's verdict: by definition when the tree has it, by name
  # (`fallback`) when it does not.
  private def plug_guard?(ref : String, path : String, line_index : Int32, fallback : String) : Bool
    verdict = if ref.starts_with?(':')
                judge.function_plug(ref[1..], path, line_index)
              else
                judge.module_plug(ref, path)
              end
    verdict.nil? ? fallback.matches?(ENFORCING_PLUG) : verdict
  end

  def self.target_techs : Array(String)
    ["elixir_bandit", "elixir_phoenix", "elixir_plug"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan routers for pipeline-scope auth
    @auth_lines.clear
    @judge = nil
    pre_scan_router_pipelines

    super
  end

  private def pre_scan_router_pipelines
    files = collect_files_by_extension(".ex")
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      next unless content.includes?("pipe_through") || content.includes?("live_session")

      @auth_lines[file] = scan_router(file, content)
    end
  end

  # Which router lines sit inside a `do ... end` block that pipes through an
  # auth pipeline (or a `live_session` mounting an auth hook). Tracked by
  # block, not by scope prefix: phx.gen.auth puts its public, guest-only and
  # authenticated routes in three `scope "/"` blocks, so a prefix match spread
  # one block's auth over every route in the app.
  private def scan_router(file : String, content : String) : Array(String?)
    lines = content.split("\n")
    cut = lines.map { |l| Noir::ElixirCalleeExtractor.strip_comment(l).strip }
    # `pipe_through [` / `:browser,` / `:auth` / `]` is matched on the
    # folded view; string contents are blanked, the patterns are atoms.
    pipe_lines = Noir::CallFold.fold(lines) { |l| Noir::ElixirCalleeExtractor.strip_comment(l) }
    pipelines = pipeline_verdicts(file, cut)

    covered = Array(String?).new(lines.size, nil)
    stack = [] of String?
    live_header = false
    live_auth : String? = nil

    cut.each_with_index do |line, index|
      pipe_line = pipe_lines[index].strip
      if pipe_line.starts_with?("pipe_through") && !stack.empty?
        if desc = pipe_through_auth(pipe_line, pipelines, file, index)
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

  # Every pipeline the router defines, and whether one of its plugs refuses
  # anonymous callers: `pipe_through :api_v1` counts when `pipeline :api_v1`
  # plugs a guard, judged by the plug's definition.
  private def pipeline_verdicts(file : String, cut : Array(String)) : Hash(String, Bool)
    verdicts = Hash(String, Bool).new
    current : String? = nil
    cut.each_with_index do |line, index|
      if m = line.match(/^pipeline\s+:(\w+)\s+do$/)
        current = m[1]
        verdicts[m[1]] = false
      elsif line == "end"
        current = nil
      elsif (name = current) && !verdicts[name] && (m = line.match(PLUG_STATEMENT))
        verdicts[name] = plug_guard?(m[1], file, index, line)
      end
    end
    verdicts
  end

  # A `pipe_through` names pipelines, function plugs (phx.gen.auth's
  # `:require_authenticated_user`) and module plugs. An atom the tree defines
  # nowhere falls back to the auth-pipeline naming convention.
  private def pipe_through_auth(line : String, pipelines : Hash(String, Bool), file : String, index : Int32) : String?
    args = line.sub(/\Apipe_through\s*/, "")
    args.scan(/(?<![\w.]):(\w+)/) do |m|
      atom = m[1]
      guard = if pipelines.has_key?(atom)
                pipelines[atom]
              else
                verdict = judge.function_plug(atom, file, index)
                verdict.nil? ? atom.matches?(AUTH_PIPELINE_ATOM) : verdict
              end
      return "Phoenix :#{atom} pipeline" if guard
    end
    args.scan(/(?<![\w.:])([A-Z]\w*(?:\.[A-Z]\w*)*)/) do |m|
      return "Phoenix #{m[1]} plug" if plug_guard?(m[1], file, index, "plug #{m[1]}")
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

      # A Phoenix router only plugs inside `pipeline` blocks, which apply
      # through `pipe_through` alone (see `check_scope_auth`), so walking up
      # from a route line would credit every route with whatever any
      # pipeline above it plugs.
      next if phoenix_router?(path_info.path)

      action = lines[line_idx].match(/^\s*def\s+(\w+[!?]?)/).try(&.[1])
      description = check_controller_plugs(path_info.path, lines, line_idx, action)
      if description.nil? && action && judge.action_refuses?(action, path_info.path, line_idx)
        description = "Phoenix #{action} action check"
      end
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

  # The module-level `plug` statements above the action (a controller's, or
  # a Plug.Router's ahead of its routes) that apply to it: a `when action in
  # [...]` / `not in` clause is honoured, one the tagger cannot resolve
  # (or any `when` on a route that is not an action) skips the plug.
  private def check_controller_plugs(path : String, lines : Array(String), action_line : Int32, action : String?) : String?
    start = action_line
    while start > 0 && !lines[start].lstrip.starts_with?("defmodule ")
      start -= 1
    end
    body_indent = lines[start].size - lines[start].lstrip.size + 2

    idx = start + 1
    while idx < action_line
      line = lines[idx]
      stripped = line.lstrip
      unless line.size - stripped.size == body_indent && stripped.matches?(/\Aplug\b/)
        idx += 1
        next
      end
      # `plug(` + newline + `Mod when action in [...]`: read the ref off
      # the joined statement.
      statement, consumed = plug_statement(lines, idx)
      if (m = statement.match(PLUG_STATEMENT)) && plug_applies?(statement, action, lines, start) && plug_guard?(m[1], path, idx, statement)
        return "Phoenix #{m[1]} plug"
      end
      idx += consumed
    end
    nil
  end

  # A `plug` statement joined across lines until its brackets balance.
  private def plug_statement(lines : Array(String), start : Int32) : Tuple(String, Int32)
    buffer = ""
    depth = 0
    consumed = 0
    while start + consumed < lines.size && consumed < 30
      code = Noir::ElixirCalleeExtractor.strip_comment(lines[start + consumed]).strip
      buffer = "#{buffer} #{code}".strip
      depth += code.count("([{") - code.count(")]}")
      consumed += 1
      break if depth <= 0 && !code.ends_with?(',')
    end
    {buffer.rchop(')').strip, consumed}
  end

  private def plug_applies?(statement : String, action : String?, lines : Array(String), module_start : Int32) : Bool
    return true unless statement.includes?("when")
    return false unless (m = statement.match(PLUG_WHEN)) && action
    return false unless actions = action_list(m[3], lines, module_start)
    negated = !m[1]?.nil? ^ !m[2]?.nil?
    actions.includes?(action) ^ negated
  end

  # The atoms of `[:a, :b]`, `@attr` or `@a ++ @b` (module attributes
  # resolved in the controller); nil when any part is something else.
  private def action_list(expr : String, lines : Array(String), module_start : Int32, depth = 0) : Set(String)?
    return if depth > 3
    actions = Set(String).new
    expr.rchop(')').split("++").each do |part|
      part = part.strip
      if part.starts_with?('[')
        part.scan(/:(\w+[!?]?)/) { |a| actions << a[1] }
      elsif attr = part.match(/\A@(\w+)\z/)
        return unless value = module_attribute(attr[1], lines, module_start)
        return unless sub = action_list(value, lines, module_start, depth + 1)
        actions.concat(sub)
      else
        return
      end
    end
    actions
  end

  private def module_attribute(name : String, lines : Array(String), module_start : Int32) : String?
    head = "@#{name} "
    (module_start...lines.size).each do |i|
      next unless lines[i].lstrip.starts_with?(head)
      statement, _ = plug_statement(lines, i)
      return statement.lchop(head.rstrip).strip
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
