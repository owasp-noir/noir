require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/rails_callback_chain"

@[Noir::TaggerFor(key: "ruby_auth", name: "Ruby Auth Tagger", desc: "Identifies Ruby authentication patterns (Devise, Pundit, CanCanCan, Warden)", order: 120)]
class RubyAuthTagger < FrameworkTagger
  # Rails before_action authentication patterns — verify who the caller is.
  # `(?<!skip_)`: `skip_before_action :doorkeeper_authorize!` removes the
  # callback; it must never read as registering it.
  BEFORE_ACTION_AUTHN_PATTERNS = [
    {/(?<!skip_)before_action\s+:authenticate_user!/, "Devise authenticate_user!"},
    {/(?<!skip_)before_action\s+:authenticate_/, "Devise authentication"},
    {/(?<!skip_)before_action\s+:require_login/, "require_login"},
    {/(?<!skip_)before_action\s+:require_authentication/, "require_authentication"},
    {/(?<!skip_)before_action\s+:check_auth/, "check_auth"},
    {/(?<!skip_)before_action\s+:verify_authenticity_token/, "CSRF verify_authenticity_token"},
    {/(?<!skip_)before_action\s+:doorkeeper_authorize!/, "Doorkeeper OAuth authorize"},
    {/(?<!skip_)before_action\s+:authenticate_with_token/, "token authentication"},
  ]

  # Rails before_action authorization — verify what the caller may do.
  BEFORE_ACTION_AUTHZ_PATTERNS = [
    {/(?<!skip_)before_action\s+:authorize/, "authorize"},
  ]

  # Union kept for the CONTROLLER_AUTH_ANY gate and the shared walk.
  BEFORE_ACTION_PATTERNS = BEFORE_ACTION_AUTHN_PATTERNS + BEFORE_ACTION_AUTHZ_PATTERNS

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
  HANAMI_AUTHN_PATTERNS = [
    {/before\s+:authenticate/, "Hanami authenticate"},
  ]
  HANAMI_AUTHZ_PATTERNS = [
    {/before\s+:authorize/, "Hanami authorize"},
  ]
  HANAMI_AUTH_PATTERNS = HANAMI_AUTHN_PATTERNS + HANAMI_AUTHZ_PATTERNS

  # Grape patterns (before blocks, http_basic, helpers)
  GRAPE_AUTH_PATTERNS = [
    {/before\s+do.*authenticate/, "Grape before authenticate"},
    {/before\s*\{\s*authenticate!/, "Grape authenticate!"},
    {/before\s*\{\s*require_auth/, "Grape require_auth"},
    {/http_basic\s+do/, "Grape http_basic auth"},
    {/helpers\s+do.*authenticate/, "Grape helpers authenticate"},
    {/\.error!\s*\(\s*['"]Unauthorized/, "Grape error! unauthorized"},
  ]

  # Roda / Rodauth authentication patterns
  RODA_AUTHN_PATTERNS = [
    {/rodauth\.require_authentication/, "Rodauth require_authentication"},
    {/rodauth\.require_auth/, "Rodauth require_auth"},
    {/rodauth\.logged_in\?/, "Rodauth logged_in?"},
    {/rodauth\.authenticated\?/, "Rodauth authenticated?"},
    {/r\.rodauth/, "Roda rodauth plugin"},
    {/r\.halt\s+401/, "Roda 401 halt"},
  ]
  RODA_AUTHZ_PATTERNS = [
    {/authorize!/, "Roda authorize!"},
  ]

  # skip_before_action marks public overrides
  SKIP_PATTERNS = [
    /skip_before_action\s+:authenticate/,
    /skip_before_action\s+:require_login/,
    /skip_before_action\s+:require_authentication/,
    # Rails 8 `rails generate authentication`: the opt-out macro its
    # `Authentication` concern defines over `skip_before_action`.
    /^\s*allow_unauthenticated_access\b/,
  ]

  # `skip_before_action :a, :b, only: [...]`: the callbacks it removes, and
  # the callbacks a `before_action` line registers.
  SKIP_CALLBACKS          = /\bskip_before_action\s+((?::\w+[!?]?\s*,?\s*)+)/
  BEFORE_ACTION_CALLBACKS = /(?<!skip_)before_action\s+((?::\w+[!?]?\s*,?\s*)+)/

  # Cheap gate for `check_controller_auth`'s backward walk, which runs to the
  # enclosing `class` — or, in a Sinatra/Grape/Roda file that has none, to line
  # 0 — for *every* endpoint in the file. Mechanically the union of the three
  # pattern sets it guards, so a line it rejects cannot match any of them; it
  # replaces 13 regex evaluations per line with one.
  CONTROLLER_AUTH_ANY = begin
    sources = [] of Regex | String
    SKIP_PATTERNS.each { |pattern| sources << pattern }
    sources << SKIP_CALLBACKS
    BEFORE_ACTION_PATTERNS.each { |pattern, _| sources << pattern }
    HANAMI_AUTH_PATTERNS.each { |pattern, _| sources << pattern }
    Regex.union(sources)
  end

  def self.target_techs : Array(String)
    ["ruby_rails", "ruby_sinatra", "ruby_hanami", "ruby_grape", "ruby_roda"]
  end

  @rails_chain : Noir::RailsCallbackChain? = nil

  def initialize(options : Hash(String, YAML::Any))
    super
    @controller_line_flags = Hash(String, Array(UInt8)).new
    @scope_lines = Hash(String, ScopeLines).new
    @flagged_line_jumps = Hash(String, Array(Int32)).new
    @callback_guards = Hash(String, String?).new
    @rejecting_defs = Hash(String, Bool).new
  end

  # Per-line flags for `check_controller_auth`, computed once per file.
  #
  # The walk runs from each action back to its enclosing `class`, so a
  # controller with N actions re-examined the same lines N times — a regex
  # and an `lstrip` allocation per line per action. Neither depends on the
  # action, so classify each line once:
  #   CONTROLLER_AUTH_LINE — matches `CONTROLLER_AUTH_ANY`; the walk runs the
  #                          full pattern checks on it
  #   CLASS_LINE           — any other line that opens a class; the walk stops
  CONTROLLER_AUTH_LINE = 1_u8
  CLASS_LINE           = 2_u8

  private def controller_line_flags(path : String, lines : Array(String)) : Array(UInt8)
    @controller_line_flags[path] ||= lines.map do |line|
      if line.matches?(CONTROLLER_AUTH_ANY)
        CONTROLLER_AUTH_LINE
      elsif line.lstrip.starts_with?("class ")
        CLASS_LINE
      else
        0_u8
      end
    end
  end

  # The locations to read guards from: the resolved handler (`articles#feed`
  # at its `def` in the controller) first, then the code paths. A route
  # declared only in `routes.rb` (`get :feed, on: :collection`) has the
  # routes file as its one code path, where no `before_action` lives.
  # ponytail: a handler without a line (inherited/implicit action) is not
  # walked; its controller's callbacks still apply.
  private def guard_locations(endpoint : Endpoint) : Array({String, Int32})
    locations = [] of {String, Int32}
    if (handler = endpoint.handler) && (path = handler.path) && (line = handler.line)
      locations << {path, line}
    end
    endpoint.details.code_paths.each do |path_info|
      if line = path_info.line
        locations << {path_info.path, line}
      end
    end
    locations.uniq!
  end

  private def check_endpoint(endpoint : Endpoint)
    guard_locations(endpoint).each do |path, line_num|
      lines = read_file_lines(path)
      next if lines.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      authn_desc : String? = nil

      # Rails/Hanami: collect controller before_action authn *and* authz.
      # Returning after the first match used to drop Devise when a closer
      # `before_action :authorize` won the walk, and skipped body authorize.
      flags = controller_line_flags(path, lines)
      # The walk below starts over from every action, so it hops from flag
      # to flag rather than stepping past each unflagged line to the class.
      jumps = nearest_match_above(@flagged_line_jumps, path, flags) { |flag| flag != 0 }
      controller = check_controller_auth(lines, line_idx, flags, jumps)
      # skip_before_action only suppresses authentication callbacks — not
      # independent authorize / CanCanCan checks in the action body.
      unless controller[:skipped]
        authn_desc = controller[:authn]
        if authn_desc.nil? && (class_idx = controller[:class_idx])
          authn_desc = inherited_authn(path, class_idx, extract_action_name(lines, line_idx))
        end
      end
      authz_desc = controller[:authz]

      # Action-body authorization (Pundit/CanCanCan) stacks with controller authn.
      if body_authz = check_action_body_auth(lines, line_idx)
        authz_desc ||= body_authz
      end

      # add_tag dedupes by (name, tagger), so authn/authz need distinct names.
      if authn_desc
        endpoint.add_tag(Tag.new("auth", "Protected by #{authn_desc}", "ruby_auth"))
      end
      if authz_desc
        endpoint.add_tag(Tag.new("authz", "Protected by #{authz_desc}", "ruby_auth"))
      end
      return if authn_desc || authz_desc || controller[:skipped] || controller[:opted_out]

      # Sinatra/Rack patterns first, then Grape (before blocks, http_basic,
      # etc.), both over the same route scope.
      scope = route_scope(path, lines, line_idx, endpoint.url)
      description = match_scope(scope, SINATRA_AUTH_PATTERNS) || match_scope(scope, GRAPE_AUTH_PATTERNS)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ruby_auth"))
        return
      end

      # Check Roda/Rodauth patterns — may yield both authn and authz.
      roda = check_roda_auth(lines, line_idx)
      if roda[:authn]
        endpoint.add_tag(Tag.new("auth", "Protected by #{roda[:authn]}", "ruby_auth"))
      end
      if roda[:authz]
        endpoint.add_tag(Tag.new("authz", "Protected by #{roda[:authz]}", "ruby_auth"))
      end
      return if roda[:authn] || roda[:authz]
    end
  end

  private def applies_to_action?(current : String, action_name : String?) : Bool
    Noir::RailsCallbackChain.applies_to_action?(current, action_name)
  end

  private def check_controller_auth(lines : Array(String), action_line : Int32, flags : Array(UInt8), jumps : Array(Int32)) : NamedTuple(authn: String?, authz: String?, skipped: Bool, opted_out: Bool, class_idx: Int32?)
    # Walk backwards to find the controller class and before_action declarations
    idx = action_line
    action_name = extract_action_name(lines, action_line)
    authn_desc : String? = nil
    authz_desc : String? = nil
    skipped = false
    skipped_callbacks = Set(String).new
    class_idx : Int32? = nil

    while idx >= 0
      idx = jumps[idx]
      break if idx < 0
      if flags[idx] == CLASS_LINE
        class_idx = idx
        break
      end

      current = lines[idx].strip

      # Check for skip_before_action that applies to this action.
      # Skip only clears authentication — keep walking for authorize callbacks.
      SKIP_PATTERNS.each do |pattern|
        skipped = true if current.matches?(pattern) && applies_to_action?(current, action_name)
      end
      # The walk runs bottom-up, so a skip is seen before the `before_action`
      # it opts this action out of.
      if (m = current.match(SKIP_CALLBACKS)) && applies_to_action?(current, action_name)
        m[1].scan(/:(\w+[!?]?)/) { |name| skipped_callbacks << name[1] }
      end
      registered = live_callbacks(current, skipped_callbacks)

      if !skipped && applies_to_action?(current, action_name)
        registered.scan(BEFORE_ACTION_CALLBACKS) do |line|
          line[1].scan(/:(\w+[!?]?)/) { |name| authn_desc ||= callback_guard(name[1]) }
        end
      end

      BEFORE_ACTION_AUTHZ_PATTERNS.each do |pattern, desc|
        if registered.matches?(pattern) && applies_to_action?(current, action_name)
          authz_desc ||= desc
        end
      end

      unless skipped
        HANAMI_AUTHN_PATTERNS.each do |pattern, desc|
          authn_desc ||= desc if current.matches?(pattern)
        end
      end
      HANAMI_AUTHZ_PATTERNS.each do |pattern, desc|
        authz_desc ||= desc if current.matches?(pattern)
      end

      if current.starts_with?("class ")
        class_idx = idx
        break
      end

      idx -= 1
    end

    # An action opted out of an auth callback is a Rails action left public,
    # not a Sinatra/Grape/Roda route for the fallback checks to re-read.
    opted_out = skipped_callbacks.any? do |callback|
      BEFORE_ACTION_PATTERNS.any? { |pattern, _| "before_action :#{callback}".matches?(pattern) }
    end
    {authn: authn_desc, authz: authz_desc, skipped: skipped, opted_out: opted_out, class_idx: class_idx}
  end

  # `line` with the `before_action` callbacks in `skipped` dropped.
  private def live_callbacks(line : String, skipped : Set(String)) : String
    return line if skipped.empty?
    return line unless m = line.match(BEFORE_ACTION_CALLBACKS)
    m[1].scan(/:(\w+[!?]?)/).reject { |name| skipped.includes?(name[1]) }.join('\n') { |name| "before_action :#{name[1]}" }
  end

  # A controller's own class body is only half its callback chain (see
  # `Noir::RailsCallbackChain`): the first callback its parents, concerns and
  # own body leave active for `action` that guards the request.
  private def inherited_authn(path : String, class_idx : Int32, action : String?) : String?
    chain = rails_chain
    leaf = chain.classes[{path, class_idx}]?
    return unless leaf && leaf.parent
    chain.resolve(leaf, action).callbacks.each do |callback|
      if desc = callback_guard(callback)
        return desc
      end
    end
  end

  # Every class and module under a `controllers` directory.
  private def rails_chain : Noir::RailsCallbackChain
    @rails_chain ||= Noir::RailsCallbackChain.new.tap do |chain|
      collect_files_by_extension(".rb").each do |path|
        next unless base_relative_path(path).includes?("controllers")
        next unless lines = read_file_lines(path)
        chain.add_file(path, lines)
      end
    end
  end

  # Lines that end the request: a 401/403, a redirect, a raise, the
  # `authenticate_or_request_with_*` / `request_http_*` helpers that answer
  # 401 themselves, or a bang auth call.
  CALLBACK_REJECTS = /\b(?:head\s+(?::unauthorized|:forbidden|401|403)|status:\s*(?::unauthorized|:forbidden|401|403)|redirect_to|redirect_back|raise|throw|halt|authenticate_or_request_with_http_\w+|request_http_\w+_authentication)\b|\w*auth\w*!/
  # An `if` whose condition only asks whether a credential was sent: the
  # rejection under it never fires for a request that carries none.
  CREDENTIAL_PRESENT_IF = /^if\s+(?!.*(?:!|\bnot\b|\.(?:nil|blank|empty)\?)).*\b(?:request|params|cookies|session|token|header|bearer|jwt|authorization)\b/i

  # The guard an authentication callback stands for, or nil when it is not
  # one. A callback the app defines itself (under `controllers/`) is read
  # rather than trusted by name: `before_action :authenticate_user` that
  # only decodes an `Authorization` header when one is present is a token
  # decoder, not a gate, and tagged every public action of the app. A name
  # with no definition in the app (Devise's `authenticate_user!`) keeps
  # its pattern description.
  private def callback_guard(callback : String) : String?
    return @callback_guards[callback] if @callback_guards.has_key?(callback)
    desc = BEFORE_ACTION_AUTHN_PATTERNS.find { |pattern, _| "before_action :#{callback}".matches?(pattern) }.try(&.[1])
    if desc
      if rails_chain.defs.has_key?(callback)
        desc = body_rejects?(callback, Set(String).new) ? "#{callback} (app-defined, rejects in its body)" : nil
      end
    end
    @callback_guards[callback] = desc
  end

  # Whether any definition of `name` can reject a request: a
  # `CALLBACK_REJECTS` line, a `super` in the callback's own body (the
  # library guard it overrides), or a call to another app method that can,
  # that is not nested under a credential-presence `if` without an `else`.
  # ponytail: nesting is read from indentation, and a condition is judged
  # by its text; a guard spelled `if token_valid?(header) ... else head 401`
  # is still read right, one hidden behind a positive credential check
  # that rejects on its own branch is not.
  private def body_rejects?(name : String, visited : Set(String)) : Bool
    return @rejecting_defs[name] if @rejecting_defs.has_key?(name)
    top = visited.empty?
    return false unless visited.add?(name)
    @rejecting_defs[name] = rails_chain.defs[name].any? do |path, def_idx|
      next false unless lines = read_file_lines(path)
      def_indent = line_indent(lines[def_idx])
      body = [] of {Int32, String}
      body << {def_indent, lines[def_idx].strip.sub(/^def\s+(?:self\.)?\w+[!?]?/, "")}
      ((def_idx + 1)...lines.size).each do |idx|
        stripped = lines[idx].strip
        next if stripped.empty? || stripped.starts_with?('#')
        break if line_indent(lines[idx]) <= def_indent
        body << {line_indent(lines[idx]), stripped}
      end
      body.each_with_index.any? do |(_, text), i|
        rejects = text.matches?(CALLBACK_REJECTS) || (top && text.matches?(/\bsuper\b/)) ||
                  text.scan(/\b[a-z_]\w*[!?]?/).any? { |m| rails_chain.defs.has_key?(m[0]) && body_rejects?(m[0], visited) }
        rejects && !credential_gated?(body, i)
      end
    end
  end

  # Whether `body[i]` sits under a `CREDENTIAL_PRESENT_IF` block (at any
  # depth) that has no `else` / `elsif` between the `if` and the line.
  private def credential_gated?(body : Array({Int32, String}), i : Int32) : Bool
    indent = body[i][0]
    (i - 1).downto(1) do |j|
      next unless body[j][0] < indent
      indent = body[j][0]
      next unless body[j][1].matches?(CREDENTIAL_PRESENT_IF)
      return true unless ((j + 1)...i).any? { |k| body[k][0] == indent && body[k][1].matches?(/^els(?:e|if)\b/) }
    end
    false
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

  private def extract_action_name(lines : Array(String), line_idx : Int32) : String?
    return if line_idx < 0 || line_idx >= lines.size
    line = lines[line_idx].strip
    match = line.match(/def\s+(\w+)/)
    match ? match[1] : nil
  end

  # Sinatra/Grape guards that cover the route at `route_line`: its own block
  # (the route line and everything indented under it), plus the `before`
  # filters, `use` middleware and `http_basic` settings of its enclosing
  # scopes above it. Statements indented deeper than the walk's current
  # scope sit inside a sibling block — an earlier route's body, or the
  # `helpers do def protected! ... end` that *defines* a guard — and are not
  # read. A fixed-size look-back read exactly those, and never the route's
  # own `protected!` call.
  # ponytail: filters declared below the route are not seen; Sinatra applies
  # them anyway — scan forward too if that shape turns up.
  private def route_scope(path : String, lines : Array(String), route_line : Int32, url : String) : Array(String)
    index = scope_lines(path, lines)
    scope = ruby_block_lines(index, route_line)
    indent = line_indent(lines[route_line])
    idx = route_line - 1
    while idx >= 0 && index.skip?(idx)
      idx -= 1
    end
    while idx >= 0 && index.indent[idx] > indent
      idx = index.prev_shallower[idx]
    end
    # From here the walk reads exactly `idx` and its `prev_level` ancestors;
    # `filter_up` visits only the filter statements among them.
    idx = index.filter_up[idx] if idx >= 0
    while idx >= 0
      stripped = index.stripped[idx]
      scope.concat(ruby_block_lines(index, idx)) if filter_covers?(stripped, url)
      idx = index.prev_level[idx]
      idx = index.filter_up[idx] if idx >= 0
    end
    scope
  end

  private def match_scope(scope : Array(String), patterns) : String?
    scope.each do |line|
      patterns.each do |pattern, desc|
        return desc if line.matches?(pattern)
      end
    end
    nil
  end

  # Per-line facts for `route_scope`, built once per file. Its walk used to
  # strip every line from the route back to the top of the file, for every
  # endpoint, so a file with N routes cost O(N²) (gitlab's Grape API: ~9s
  # under `-T`). The two hops jump straight over the lines the walk
  # ignores: `prev_shallower` past a run indented deeper than the scope it
  # is in, `prev_level` past the body of a sibling statement, and
  # `filter_up` to the closest `before`/`use`/`http_basic` statement among
  # a line and its `prev_level` ancestors — the walk otherwise still read
  # every sibling, which is every route of a Rails `routes.rb`. All three
  # are -1 when there is none and only meaningful on lines that aren't
  # `skip?`.
  private record ScopeLines,
    stripped : Array(String),
    indent : Array(Int32),
    prev_shallower : Array(Int32),
    prev_level : Array(Int32),
    filter_up : Array(Int32) do
    def skip?(idx : Int32) : Bool
      line = stripped[idx]
      line.empty? || line.starts_with?('#')
    end
  end

  private def scope_lines(path : String, lines : Array(String)) : ScopeLines
    @scope_lines[path] ||= begin
      stripped = lines.map(&.strip)
      indent = lines.map { |line| line_indent(line) }
      prev_shallower = Array(Int32).new(lines.size, -1)
      prev_level = Array(Int32).new(lines.size, -1)
      filter_up = Array(Int32).new(lines.size, -1)
      shallower = [] of Int32 # line indexes, indents strictly increasing
      level = [] of Int32     # line indexes, indents non-decreasing
      lines.each_index do |idx|
        line = stripped[idx]
        next if line.empty? || line.starts_with?('#')
        while (last = shallower.last?) && indent[last] >= indent[idx]
          shallower.pop
        end
        while (last = level.last?) && indent[last] > indent[idx]
          level.pop
        end
        prev_shallower[idx] = shallower.last? || -1
        prev_level[idx] = level.last? || -1
        filter_up[idx] = if line.matches?(/^(?:before|use|http_basic)\b/)
                           idx
                         elsif (parent = prev_level[idx]) >= 0
                           filter_up[parent]
                         else
                           -1
                         end
        shallower << idx
        level << idx
      end
      ScopeLines.new(stripped, indent, prev_shallower, prev_level, filter_up)
    end
  end

  # `before '/admin/*' do` only runs for matching paths; a bare `before do`
  # runs for all. The pattern is matched against the URL's tail, since a
  # filter inside a `namespace` is relative to it.
  private def filter_covers?(statement : String, url : String) : Bool
    return true unless m = statement.match(/^before\s*\(?\s*['"]([^'"]+)['"]/)
    pattern = Regex.escape(m[1]).gsub("\\*", ".*").gsub(/:\w+/, "[^/]+")
    url.matches?(Regex.new("#{pattern}\\z"))
  end

  # The line at `idx` and the lines indented under it — its block body.
  private def ruby_block_lines(index : ScopeLines, idx : Int32) : Array(String)
    block = [index.stripped[idx]]
    indent = index.indent[idx]
    ((idx + 1)...index.stripped.size).each do |j|
      stripped = index.stripped[j]
      next if stripped.empty?
      break if index.indent[j] <= indent
      block << stripped
    end
    block
  end

  private def line_indent(line : String) : Int32
    line.size - line.lstrip.size
  end

  private def check_roda_auth(lines : Array(String), route_line : Int32) : NamedTuple(authn: String?, authz: String?)
    # Roda uses route blocks; rodauth calls are usually inside the handler or just above
    start_idx = [route_line - 12, 0].max
    end_idx = [route_line + 8, lines.size - 1].min
    authn_desc : String? = nil
    authz_desc : String? = nil

    (start_idx..end_idx).each do |idx|
      current = lines[idx].strip

      RODA_AUTHN_PATTERNS.each do |pattern, desc|
        authn_desc ||= desc if current.matches?(pattern)
      end
      RODA_AUTHZ_PATTERNS.each do |pattern, desc|
        authz_desc ||= desc if current.matches?(pattern)
      end
    end

    {authn: authn_desc, authz: authz_desc}
  end
end
