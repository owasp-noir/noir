require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/rails_callback_chain"
require "../../../miniparsers/cancan_ability"
require "../../../utils/ruby_inflector"

@[Noir::TaggerFor(key: "ruby_auth", name: "Ruby Auth Tagger", desc: "Identifies Ruby authentication patterns (Devise, Pundit, CanCanCan, Warden)", order: 120)]
class RubyAuthTagger < FrameworkTagger
  # Rails before_action authentication patterns — verify who the caller is.
  # `(?<!skip_)`: `skip_before_action :doorkeeper_authorize!` removes the
  # callback; it must never read as registering it.
  BEFORE_ACTION_AUTHN_PATTERNS = [
    {/(?<!skip_)before_action\s+:authenticate_user!/, "Devise authenticate_user!"},
    {/(?<!skip_)before_action\s+:authenticate_resource_owner!/, "Doorkeeper resource_owner_authenticator"},
    {/(?<!skip_)before_action\s+:authenticate_/, "Devise authentication"},
    {/(?<!skip_)before_action\s+:require_login/, "require_login"},
    {/(?<!skip_)before_action\s+:require_authentication/, "require_authentication"},
    {/(?<!skip_)before_action\s+:check_auth/, "check_auth"},
    {/(?<!skip_)before_action\s+:verify_authenticity_token/, "CSRF verify_authenticity_token"},
    {/(?<!skip_)before_action\s+:doorkeeper_authorize!/, "Doorkeeper OAuth authorize"},
    {/(?<!skip_)before_action\s+:authenticate_with_token/, "token authentication"},
    {/(?<!skip_)before_action\s+:require_(?:authenticated_)?user!?(?!\w)/, "require_user"},
  ]

  # Rails before_action authorization — verify what the caller may do.
  BEFORE_ACTION_AUTHZ_PATTERNS = [
    {/(?<!skip_)before_action\s+:authorize/, "authorize"},
  ]

  # Union kept for the CONTROLLER_AUTH_ANY gate and the shared walk.
  BEFORE_ACTION_PATTERNS = BEFORE_ACTION_AUTHN_PATTERNS + BEFORE_ACTION_AUTHZ_PATTERNS

  # Pundit / CanCanCan authorization in action body. `\b`: not the
  # `doorkeeper_authorize!` / `authorize_if_got_token!` an API calls.
  ACTION_AUTH_PATTERNS = [
    {/\bauthorize!/, "CanCanCan authorize!"},
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
    {/\bauthorize!/, "Roda authorize!"},
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

  # `skip_before_action :a, :b, only: [...]`: the callbacks it removes.
  SKIP_CALLBACKS = /\bskip_before_action\s+((?::\w+[!?]?\s*,?\s*)+)/

  # Cheap gate for `check_controller_auth`'s backward walk, which runs to the
  # enclosing `class` — or, in a Sinatra/Grape/Roda file that has none, to line
  # 0 — for *every* endpoint in the file. Mechanically the union of the three
  # pattern sets it guards, so a line it rejects cannot match any of them; it
  # replaces 13 regex evaluations per line with one.
  CONTROLLER_AUTH_ANY = begin
    sources = [] of Regex | String
    SKIP_PATTERNS.each { |pattern| sources << pattern }
    sources << SKIP_CALLBACKS
    sources << Noir::RailsCallbackChain::BLOCK_CALLBACK
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
    @callback_authz = Hash(String, String?).new
    @pundit_verdicts = Hash(String, Symbol).new
    @callback_exits = Hash({String, String}, Bool).new
    @rejecting_defs = Hash(String, Bool).new
    @denying_helpers = Hash(String, Bool).new
    @denies_anonymous = Hash(String, Bool).new
    @deny_settings = Hash(String, String).new
    @caller_ivars = Hash(String, Array(String)).new
    @cancan_verdicts = Hash({String, String, String, Bool}, Bool).new
    @cancan_abilities = Hash({String, String}, Noir::CanCanAbility?).new
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
      action = extract_action_name(lines, line_idx)
      # An action a concern or parent class defines runs with the routed
      # controller's chain alone: the defining file's own callbacks and
      # skips count only as far as that chain carries them.
      dispatch = endpoint.handler.try(&.dispatch_path).try { |dispatch_path| rails_chain.controller_in(dispatch_path) } if endpoint.handler.try(&.path) == path
      skipped = opted_out = false
      if dispatch
        routed = chain_guards(dispatch, action)
        authn_desc = routed[:authn]
        authz_desc = routed[:authz]
      else
        own = rails_chain.controller_in(path)
        chain = own.try { |leaf| rails_chain.resolve(leaf, action) }
        controller = check_controller_auth(lines, line_idx, flags, jumps, chain, own)
        authz_desc = controller[:authz]
        skipped = controller[:skipped]
        opted_out = controller[:opted_out]
        # skip_before_action only suppresses authentication callbacks — not
        # independent authorize / CanCanCan checks in the action body.
        unless skipped
          authn_desc = controller[:authn]
          leaf = controller[:class_idx].try { |class_idx| rails_chain.classes[{path, class_idx}]? }
          if leaf && leaf.parent && (authn_desc.nil? || setting_lifted?(authn_desc) || authz_desc.nil?)
            inherited = chain_guards(leaf, action)
            authn_desc = stronger(authn_desc, inherited[:authn])
            authz_desc ||= inherited[:authz]
          end
        end
      end

      # Action-body authorization (Pundit/CanCanCan) stacks with controller authn.
      body = check_action_body_auth(lines, line_idx, action)
      authz_desc ||= body[:authz]
      authz_desc ||= (dispatch || rails_chain.controller_in(path)).try { |cancan_leaf| cancan_refuses(cancan_leaf, action, endpoint.url.scan(/:(\w+)/).map(&.[1])) }

      # add_tag dedupes by (name, tagger), so authn/authz need distinct names.
      if authn_desc
        endpoint.add_tag(Tag.new("auth", "Protected by #{authn_desc}", "ruby_auth"))
      end
      if authz_desc
        endpoint.add_tag(Tag.new("authz", "Protected by #{authz_desc}", "ruby_auth"))
      end
      # The action's only check is a Pundit query a nil caller passes.
      if authn_desc.nil? && authz_desc.nil? && (policy = body[:anonymous])
        endpoint.add_tag(Tag.new("anonymous", "Pundit #{policy} admits anonymous callers", "ruby_auth"))
      end
      return if authn_desc || authz_desc || body[:anonymous] || skipped || opted_out || dispatch

      # Sinatra/Rack patterns first, then Grape (before blocks, http_basic,
      # etc.), both over the same route scope.
      scope = route_scope(path, lines, line_idx, endpoint.url)
      description = match_scope(scope, SINATRA_AUTH_PATTERNS) || match_scope(scope, GRAPE_AUTH_PATTERNS)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ruby_auth"))
        return
      end

      # Roda/Rodauth patterns, only on Roda routes: a Rails controller's
      # `doorkeeper_authorize!` read as "Roda authorize!".
      next unless endpoint.details.technology == "ruby_roda"
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

  private def check_controller_auth(lines : Array(String), action_line : Int32, flags : Array(UInt8), jumps : Array(Int32), chain : Noir::RailsCallbackChain::Resolution?, leaf : Noir::RailsCallbackChain::Klass?) : NamedTuple(authn: String?, authz: String?, skipped: Bool, opted_out: Bool, class_idx: Int32?)
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

      current = Noir::RailsCallbackChain.statement(lines, idx)

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
      if applies_to_action?(current, action_name) && !Noir::RailsCallbackChain.conditional?(current)
        Noir::RailsCallbackChain.before_action_callbacks(current).each do |callback|
          next if skipped_callbacks.includes?(callback) || exits_for?(callback, leaf)
          authn_desc = stronger(authn_desc, callback_guard(callback, chain)) unless skipped
          authz_desc ||= callback_authz(callback, action_name, chain.try(&.paths) || [] of String)
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

  # A controller's own class body is only half its callback chain (see
  # `Noir::RailsCallbackChain`): the callbacks its parents, concerns and own
  # body leave active for `action` that guard the request — the first
  # authentication one (one no setting lifts, when there is one) and the
  # first authorization one.
  private def chain_guards(leaf : Noir::RailsCallbackChain::Klass, action : String?) : NamedTuple(authn: String?, authz: String?)
    resolved = rails_chain.resolve(leaf, action)
    authn : String? = nil
    authz : String? = nil
    resolved.callbacks.each do |callback|
      next if resolved.conditional.includes?(callback) || exits_for?(callback, leaf)
      guard = callback_guard(callback, resolved)
      gate = callback_authz(callback, action, resolved.paths)
      # `skip_before_action :x, if: -> { ... }`: a request value the caller
      # sends lifts it at will; anything else is the app's to decide.
      if lift = resolved.lifted[callback]?
        next if lift.matches?(/\b(?:request|params)\b/)
        note = "; `skip_before_action #{lift}` decides; #{SETTING_LIFTED}"
        guard = guard.try { |desc| "#{desc}#{note}" }
        gate = gate.try { |desc| "#{desc}#{note}" }
      end
      authn = stronger(authn, guard)
      authz ||= gate
    end
    {authn: authn, authz: authz}
  end

  # Whether `callback` returns before refusing anyone for `leaf`'s
  # requests: a leading `return if controller_name.in?(PUBLIC)` whose
  # constant lists the controller, or `return if
  # self.class.module_parent.to_s == "Admin"` for a controller in `Admin`.
  # Exits on anything else are left to `denies_anonymous?`.
  private def exits_for?(callback : String, leaf : Noir::RailsCallbackChain::Klass?) : Bool
    return false unless leaf
    controller = leaf.name.split("::").last.underscore.rchop("_controller")
    @callback_exits.put_if_absent({callback, leaf.name}) do
      (rails_chain.defs[callback]? || [] of {String, Int32}).any? do |path, def_idx|
        next false unless lines = read_file_lines(path)
        body = def_bodies(callback, [{path, def_idx}]).first? || [] of {Int32, String}
        body[1..].take_while { |_, text| !text.matches?(DENY_RESPONSE) && !text.matches?(SOFT_DENY) }.any? do |_, text|
          next false unless m = text.match(/\Areturn\b[^#]*?\s+if\s+(.+)\z/)
          condition = m[1].strip
          if c = condition.match(/\Acontroller_name\.in\?\(\s*([A-Z]\w*)\s*\)\z|\A([A-Z]\w*)\.include\?\(\s*controller_name\s*\)\z/)
            constant_words(lines, c[1]? || c[2]).includes?(controller)
          elsif c = condition.match(/\Aself\.class\.module_parent(?:\.to_s|\.name)?\s*==\s*["']?([A-Z][\w:]*)["']?\z/)
            leaf.namespace == c[1]
          else
            false
          end
        end
      end
    end
  end

  # The words of `NAME = %w[...]` (or `["a", "b"]`) in `lines`.
  private def constant_words(lines : Array(String), name : String) : Array(String)
    return [] of String unless idx = lines.index(&.matches?(/\A\s*#{name}\s*=/))
    text = lines[idx].sub(/\A\s*#{name}\s*=/, "")
    j = idx + 1
    while text.count("[(") > text.count("])") && j < lines.size && j - idx < 100
      text = "#{text} #{lines[j]}"
      j += 1
    end
    text.scan(/\b[a-z_]\w*\b/).map(&.[0]).reject { |word| {"w", "i", "freeze"}.includes?(word) }
  end

  # The marker `denies_anonymous?` leaves on a guard an app setting decides.
  SETTING_LIFTED = "a setting can make it public"

  private def setting_lifted?(desc : String?) : Bool
    !!desc.try(&.includes?(SETTING_LIFTED))
  end

  # `current` unless it is nil or a setting lifts it and `other` is a guard
  # no setting lifts.
  private def stronger(current : String?, other : String?) : String?
    return other if current.nil?
    other && setting_lifted?(current) && !setting_lifted?(other) ? other : current
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
  CALLBACK_REJECTS = /\b(?:head\s+(?::unauthorized|:forbidden|401|403)|status(?::|\s*=>)\s*(?::unauthorized|:forbidden|401|403)|redirect_to|redirect_back|raise|throw|halt|authenticate_or_request_with_http_\w+|request_http_\w+_authentication)\b|\w*auth\w*!/
  # An `if` whose condition only asks whether a credential was sent: the
  # rejection under it never fires for a request that carries none.
  CREDENTIAL_PRESENT_IF = /^if\s+(?!.*(?:!|\bnot\b|\.(?:nil|blank|empty)\?)).*\b(?:request|params|cookies|session|token|header|bearer|jwt|authorization)\b/i
  # `doorkeeper_authorize!(*scopes) if doorkeeper_token`: a statement whose
  # trailing `if` is only a credential being present.
  CREDENTIAL_PRESENT_MODIFIER = /\sif\s+@?\w*(?:token|session|header|bearer|jwt|authorization)\w*(?:\.present\?)?\z/i

  # The guard an authentication callback stands for, or nil when it is not
  # one. A callback the app defines itself (under `controllers/`) is read
  # rather than trusted by name: `before_action :authenticate_user` that
  # only decodes an `Authorization` header when one is present is a token
  # decoder, not a gate, and tagged every public action of the app. A name
  # with no definition in the app (Devise's `authenticate_user!`) keeps
  # its pattern description.
  private def callback_guard(callback : String, chain : Noir::RailsCallbackChain::Resolution?) : String?
    ivars = caller_ivars_before(callback, chain)
    paths = chain.try(&.paths) || [] of String
    key = deny_key(callback, ivars, paths)
    return @callback_guards[key] if @callback_guards.has_key?(key)
    desc = BEFORE_ACTION_AUTHN_PATTERNS.find { |pattern, _| "before_action :#{callback}".matches?(pattern) }.try(&.[1])
    if desc
      if rails_chain.defs.has_key?(callback)
        desc = body_rejects?(callback, Set(String).new) ? "#{callback} (app-defined, rejects in its body)" : nil
      elsif !library_guard_rejects?(callback)
        desc = nil
      end
    elsif rails_chain.defs.has_key?(callback) && denies_anonymous?(callback, ivars, paths)
      desc = if setting = @deny_settings[key]?
               "#{callback} (app-defined, refuses callers without a credential; `#{setting}` decides; #{SETTING_LIFTED})"
             else
               "#{callback} (app-defined, refuses callers without a credential)"
             end
    end
    @callback_guards[key] = desc
  end

  # Doorkeeper's authenticators run a block from the app's
  # `config/initializers/doorkeeper.rb`; `current_user || redirect_to(...)`
  # rejects, `User.find_by(id: session[:user_id])` alone lets anyone in.
  DOORKEEPER_BLOCKS = {"authenticate_resource_owner!" => "resource_owner_authenticator", "authenticate_admin!" => "admin_authenticator"}

  # Whether the library method `name` an app callback calls (or overrides
  # and calls `super` on) can reject. Only Doorkeeper's authenticators are
  # read; any other library guard is trusted by name, as is an
  # authenticator the app does not configure (Doorkeeper then answers 403).
  private def library_guard_rejects?(name : String) : Bool
    return true unless option = DOORKEEPER_BLOCKS[name]?
    return true unless lines = collect_files_by_extension(".rb").find(&.ends_with?("/initializers/doorkeeper.rb")).try { |path| read_file_lines(path) }
    return true unless start = lines.index(&.lstrip.starts_with?(option))
    block = [lines[start]] + lines[(start + 1)..].take_while { |source| source.strip.empty? || line_indent(source) > line_indent(lines[start]) }
    block.any? { |source| !source.strip.starts_with?('#') && source.matches?(CALLBACK_REJECTS) }
  end

  # The same reading for an authorization callback: `authorize_if_got_token!`
  # that only checks scopes when a token was sent lets anonymous callers in.
  # An app-defined one guards when its body rejects, or calls Pundit
  # `authorize` with a policy query that refuses a nil user.
  private def callback_authz(callback : String, action : String?, paths : Array(String)) : String?
    key = "#{callback}|#{action}|#{own_defs(callback, paths).join(',')}"
    return @callback_authz[key] if @callback_authz.has_key?(key)
    desc = BEFORE_ACTION_AUTHZ_PATTERNS.find { |pattern, _| "before_action :#{callback}".matches?(pattern) }.try(&.[1])
    if desc && rails_chain.defs.has_key?(callback)
      desc = if policy = pundit_refuses(callback, action, paths)
               "#{callback} (app-defined, Pundit #{policy} refuses a nil user)"
             elsif body_rejects?(callback, Set(String).new)
               desc
             end
    end
    @callback_authz[key] = desc
  end

  # The policy query (`InternalPolicy#access?`) a body line of `name`
  # asks through Pundit `authorize` that refuses a nil user, under no
  # condition that needs a credential; nil when there is none.
  private def pundit_refuses(name : String, action : String?, paths : Array(String)) : String?
    def_bodies(name, own_defs(name, paths)).each do |body|
      body.each_with_index do |(_, text), i|
        code = code_only(text)
        next unless code.matches?(PUNDIT_AUTHORIZE)
        next if credential_gated?(body, i) || credential_present_modifier?(code)
        verdict, label = pundit_verdict(code, action)
        return label if verdict == :refuses
      end
    end
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
    @rejecting_defs[name] = def_bodies(name).any? do |body|
      body.each_with_index.any? do |(_, text), i|
        rejects = text.matches?(CALLBACK_REJECTS) || (top && text.matches?(/\bsuper\b/) && library_guard_rejects?(name)) ||
                  text.scan(/\b[a-z_]\w*[!?]?/).any? { |m| rails_chain.defs.has_key?(m[0]) && body_rejects?(m[0], visited) }
        rejects && !credential_gated?(body, i) && !text.matches?(CREDENTIAL_PRESENT_MODIFIER)
      end
    end
  end

  # Each app definition of `name` as `{indent, stripped line}` rows: the
  # `def` line's tail first, then its body, blanks and comments dropped.
  private def def_bodies(name : String, defs = rails_chain.defs[name]? || [] of {String, Int32}) : Array(Array({Int32, String}))
    defs.compact_map do |path, def_idx|
      next unless lines = read_file_lines(path)
      def_indent = line_indent(lines[def_idx])
      body = [] of {Int32, String}
      body << {def_indent, lines[def_idx].strip.sub(/^def\s+(?:self\.)?\w+[!?]?/, "")}
      ((def_idx + 1)...lines.size).each do |idx|
        stripped = lines[idx].strip
        next if stripped.empty? || stripped.starts_with?('#')
        break if line_indent(lines[idx]) <= def_indent
        body << {line_indent(lines[idx]), stripped}
      end
      body
    end
  end

  # An explicit 401/403 answer.
  DENY_RESPONSE = /\bhead\s*\(?\s*(?::unauthorized|:forbidden|401|403)\b|\bstatus(?::|\s*=>)\s*(?::unauthorized\b|:forbidden\b|40[13]\b)/
  # The words a request credential is spelled with.
  CREDENTIAL_WORD = /token|session|bearer|jwt|authoriz|api_?key|signature|hmac|secret|password|current_user|signed_in|logged_in/i
  # `return if <no credential>` / `return unless <credential>`.
  ANONYMOUS_EXIT     = /^return\b.*\s(if|unless)\s+(.+)\z/
  CONDITION_MODIFIER = /\s(if|unless)\s+(.+)\z/
  BLOCK_CONDITION    = /^(if|unless|elsif)\s+(.+)/
  NEGATED            = /!|\bnot\b|\.(?:nil|blank|empty)\?/

  # A callback whose name says nothing (`set_platform_app`) guards when its
  # definition answers 401/403 unconditionally, or on a condition that
  # reads the caller's credential: `render ..., status: :unauthorized if
  # @app.blank?` after `@app = @access_token.owner`. A 401 on anything
  # else (`unless account.active?`, an unknown Host) refuses a state of
  # the app, not an anonymous caller; an early `return` when no credential
  # was sent, or a credential-presence `if` around it, lets one through.
  # A redirect or another 4xx (`redirect_to "/login"`, `status: 400`) is a
  # refusal only on a credential-absent condition: unconditional, it is a
  # page move, not a gate. A call to another app method that refuses
  # anonymous callers is one, on whatever conditions it sits under.
  # A deny under a condition that needs the credential present (`if
  # current_user && !current_user.admin?`) lets an anonymous caller pass.
  # ponytail: one assignment hop links a condition to a credential (or the
  # instance variable an earlier callback sets from one, `ivars`); a longer
  # chain reads as no guard.
  private def denies_anonymous?(name : String, ivars : Array(String), paths : Array(String), visited : Set(String) = Set(String).new) : Bool
    top = visited.empty?
    key = deny_key(name, ivars, paths)
    return @denies_anonymous[key] if top && @denies_anonymous.has_key?(key)
    return false unless visited.add?(name)
    # Each deny that refuses an anonymous caller: the setting it also waits
    # on (nil when none decides) and the request-value conditions it needs.
    denies = [] of {String?, Array({String, Bool})}
    def_bodies(name, own_defs(name, paths)).each do |body|
      assigns = Hash(String, String).new
      body.each { |_, text| (m = text.match(/^(@?\w+)\s*\|{0,2}=(?!=)\s*(.+)/)) && (assigns[m[1]] = m[2]) }
      body.each_with_index do |(_, text), i|
        strict = text.matches?(DENY_RESPONSE) || text.scan(/\b[a-z_]\w*[!?]?/).any? { |m| always_denies?(m[0]) } ||
                 text.scan(BARE_CALL).any? { |m| m[0] != name && rails_chain.defs.has_key?(m[0]) && denies_anonymous?(m[0], ivars, paths, visited) }
        next unless strict || text.matches?(SOFT_DENY)
        next if credential_gated?(body, i) || text.matches?(CREDENTIAL_PRESENT_MODIFIER)
        next unless conditions = deny_conditions(body, i)
        parts = deny_parts(conditions)
        next if parts.any? { |c, when_true| credential_present?(c, when_true, assigns, ivars) }
        next unless (strict && parts.empty?) || parts.any? { |c, when_true| credential_absent?(c, when_true, assigns, ivars) }
        chosen = parts.select { |c, _| c.matches?(PARAMS_READ) && !credential_condition?(c, assigns, ivars) }
        denies << {parts.find { |c, _| app_setting?(c) }.try(&.[0].lchop('!').strip), chosen}
      end
    end
    # `return if params[:page].to_i <= 1000` above the only 401: the caller
    # picks a request value that skips every deny. An `if/else` on the value
    # that denies on both arms leaves no such value.
    avoidable = !denies.empty? && denies.first[1].any? do |part|
      denies.all? { |_, chosen| chosen.includes?(part) }
    end
    result = !denies.empty? && !avoidable
    if top
      @denies_anonymous[key] = result
      settings = denies.map(&.[0])
      first = settings.first?
      @deny_settings[key] = first if result && first && settings.none?(Nil)
    end
    result
  end

  # The definitions of `name` Ruby finds for a controller whose ancestry
  # spans `paths`: those in its own files when there are any (two
  # controllers each defining a private `ensure_member` are two methods),
  # else every one the app has.
  private def own_defs(name : String, paths : Array(String)) : Array({String, Int32})
    defs = rails_chain.defs[name]? || [] of {String, Int32}
    own = defs.select { |path, _| paths.includes?(path) }
    own.empty? ? defs : own
  end

  private def deny_key(name : String, ivars : Array(String), paths : Array(String)) : String
    "#{name}|#{ivars.join(',')}|#{own_defs(name, paths).join(',')}"
  end

  # A request value read off `params`.
  PARAMS_READ = /(?<![\w.@])params\b/
  # The other side of a comparison that makes a request value a credential
  # whatever its key: a secret, the app's credentials, ENV or a config read.
  SECRET_SOURCE = /\bENV\b|\bcredentials\b|\bsecrets?\b|Rails\.(?:application|configuration)\b|(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\.[a-z_]\w*/

  # A condition that reads the app's configuration rather than the request:
  # a call on a constant (`Settings::UserExperience.public`,
  # `Rails.configuration.x.private_mode`, `Flipper.enabled?(:x)`) or `ENV`.
  # A deny that waits on one is a guard an operator can switch off.
  # `Current.user` (CurrentAttributes) is the caller, not a setting.
  APP_SETTING = /\A!?\s*(?:(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*(?:\.[a-z_]\w*[?!]?(?:\([^()]*\))?)+|ENV\s*(?:\[|\.fetch\b))/

  private def app_setting?(condition : String) : Bool
    condition.matches?(APP_SETTING) && !condition.matches?(CREDENTIAL_WORD) && !condition.matches?(/\bCurrent\./)
  end

  # A call with no receiver: `require_login`, not `cookies.delete`.
  BARE_CALL = /(?<![.:@\w])[a-z_]\w*[!?]?/
  # A redirect, or a 4xx answer other than 401/403, from a callback.
  SOFT_DENY = /\bredirect_(?:to|back(?:_or_to)?)\b|\bhead\s*\(?\s*(?::bad_request|:not_found|4\d\d)\b|\bstatus(?::|\s*=>)\s*(?::bad_request\b|:not_found\b|4\d\d\b)/

  # Whether the helper `name` (`render_unauthorized`) answers 401/403 on a
  # line of its own body that no condition guards.
  private def always_denies?(name : String) : Bool
    return false unless rails_chain.defs.has_key?(name)
    @denying_helpers.put_if_absent(name) do
      def_bodies(name).any? do |body|
        body[1..].any? { |indent, text| indent == body[1][0] && text.matches?(DENY_RESPONSE) && !text.matches?(CONDITION_MODIFIER) }
      end
    end
  end

  # The conditions the deny at `body[i]` sits under, each with whether the
  # deny runs when it is true: its own `if`/`unless` modifier, the blocks
  # around it (an `else` branch runs when its `if` is false), and the
  # `return if ...` exits above it. nil when one of those exits lets a
  # caller with no credential out.
  private def deny_conditions(body : Array({Int32, String}), i : Int32) : Array({String, Bool})?
    conditions = [] of {String, Bool}
    if m = body[i][1].match(CONDITION_MODIFIER)
      conditions << {m[2], m[1] == "if"}
    end
    indent = body[i][0]
    branch_at : Int32? = nil # an `else`/`elsif` whose `if` is still above
    (i - 1).downto(1) do |j|
      indent_j, text = body[j]
      # `return head :unauthorized unless ...` above is a deny of its own.
      if (m = text.match(ANONYMOUS_EXIT)) && !text.matches?(DENY_RESPONSE)
        negated = m[2].matches?(NEGATED)
        return if m[2].matches?(CREDENTIAL_WORD) && (m[1] == "if" ? negated : !negated)
        conditions << {m[2], m[1] != "if"}
      elsif indent_j < indent || indent_j == branch_at
        from_branch = indent_j == branch_at
        indent = indent_j
        branch_at = text.matches?(/^(?:else|elsif)\b/) ? indent_j : nil
        if block = text.match(BLOCK_CONDITION)
          conditions << {block[2], (block[1] != "unless") != from_branch}
        elsif text.matches?(/^(?:case|when)\b/)
          conditions << {text, true}
        end
      end
    end
    conditions
  end

  # Whether the deny fires for a caller without the credential: the
  # condition reads one and tests its absence (`if @app.blank?`, `unless
  # valid_token?`). `if current_user&.suspended?` refuses a present user,
  # which lets an anonymous caller through.
  private def credential_absent?(condition : String, when_true : Bool, assigns : Hash(String, String), ivars : Array(String)) : Bool
    credential_condition?(condition, assigns, ivars) && condition.matches?(NEGATED) == when_true
  end

  # The deny runs only when the caller has the credential.
  private def credential_present?(condition : String, when_true : Bool, assigns : Hash(String, String), ivars : Array(String)) : Bool
    credential_condition?(condition, assigns, ivars) && condition.matches?(NEGATED) != when_true
  end

  # Each conjunct a deny needs, with the value it needs: under `if a && b`
  # both true, under `unless a || b` (or an `else`) both false.
  private def deny_parts(conditions : Array({String, Bool})) : Array({String, Bool})
    conditions.flat_map do |condition, when_true|
      condition.split(when_true ? /&&|\band\b/ : /\|\||\bor\b/).map { |part| {part.strip, when_true} }
    end
  end

  # An instance variable is the caller's credential by the assignment
  # that runs for this request: one in the callback's own body first
  # (`@user = User.find_by(username: params[:id])` is a looked-up record),
  # else what the callbacks before it in the controller's chain left.
  private def credential_condition?(condition : String, assigns : Hash(String, String), ivars : Array(String)) : Bool
    return true if condition.matches?(CREDENTIAL_WORD)
    return true if condition.matches?(PARAMS_READ) && condition.matches?(/[!=]=|secure_compare/) &&
                   condition.gsub(/(?<![\w.@])params\s*(?:\[[^\]]*\]|\.\w+\([^)]*\))*/, "").matches?(SECRET_SOURCE)
    condition.scan(/@?\w+/).any? do |m|
      if value = assigns[m[0]]?
        value.matches?(CREDENTIAL_WORD)
      else
        ivars.includes?(m[0])
      end
    end
  end

  # Where a request carries its credential.
  CREDENTIAL_SOURCE = /\b(?:session|cookies|request\.headers)\b|token|bearer|jwt|authoriz|api_?key/i

  # The instance variables the callbacks that run before `callback` in
  # `chain` leave holding the caller: `@user = user` under `if session[:u]
  # && (user = User.find_by(session_token: ...))`, `@current_user ||=
  # User.find_by(id: session[:user_id])`, `@user = current_user`. A later
  # assignment replaces an earlier one, so a `set_account` that loads
  # `@account = Account.find(params[:account_id])` leaves a target, not
  # the caller. A record looked up through the caller
  # (`current_user.accounts.find(...)`) is not the caller either.
  # ponytail: each callback's defs are read wherever the app defines that
  # name, preferring the files of the controller's own ancestry.
  private def caller_ivars_before(callback : String, chain : Noir::RailsCallbackChain::Resolution?) : Array(String)
    return [] of String unless chain
    callbacks = chain.callbacks
    callbacks = callbacks[0, callbacks.index(callback) || callbacks.size]
    @caller_ivars.put_if_absent("#{callbacks.join(',')}|#{chain.paths.join(',')}") do
      state = Hash(String, Bool).new
      callbacks.each do |name|
        next if name == callback
        defs = rails_chain.defs[name]? || [] of {String, Int32}
        own = defs.select { |path, _| chain.paths.includes?(path) }
        def_bodies(name, own.empty? ? defs : own).each do |body|
          body.each_with_index do |(indent, text), i|
            next unless m = text.match(/^(@\w+)\s*\|{0,2}=(?!=)\s*(.+)/)
            state[m[1]] = caller_assignment?(body, i, indent, m[2])
          end
        end
      end
      state.select { |_, caller| caller }.keys.sort!
    end
  end

  private def caller_assignment?(body : Array({Int32, String}), i : Int32, indent : Int32, value : String) : Bool
    return true if value.matches?(CREDENTIAL_SOURCE) || value.matches?(/\Acurrent_(?:user|account)\z/)
    depth = indent
    (i - 1).downto(1) do |j|
      next unless body[j][0] < depth
      depth = body[j][0]
      return true if (block = body[j][1].match(BLOCK_CONDITION)) && block[2].matches?(CREDENTIAL_SOURCE)
    end
    false
  end

  # Whether `body[i]` sits under a `CREDENTIAL_PRESENT_IF` block (at any
  # depth) that has no `else` / `elsif` between the `if` and the line.
  private def credential_gated?(body : Array({Int32, String}), i : Int32) : Bool
    indent = body[i][0]
    (i - 1).downto(1) do |j|
      next unless body[j][0] < indent
      indent = body[j][0]
      next unless body[j][1].matches?(CREDENTIAL_PRESENT_IF)
      # `if params[:format] == "json"` / `if request.format.json?` asks
      # about the request, not whether it carries a credential.
      next if body[j][1].matches?(/\b(?:request|params)\b/) && !body[j][1].matches?(/\b(?:cookies|session|token|header|bearer|jwt|authorization)\b/i) &&
              !body[j][1].matches?(CREDENTIAL_WORD)
      return true unless ((j + 1)...i).any? { |k| body[k][0] == indent && body[k][1].matches?(/^els(?:e|if)\b/) }
    end
    false
  end

  private def check_action_body_auth(lines : Array(String), action_line : Int32, action : String?) : NamedTuple(authz: String?, anonymous: String?)
    # Scan forward from the action definition for auth calls
    idx = action_line + 1
    end_idx = [action_line + 20, lines.size - 1].min
    anonymous : String? = nil

    while idx <= end_idx
      current = code_only(lines[idx].strip)
      # Stop at next method definition
      break if current.starts_with?("def ") && idx > action_line

      if current.matches?(PUNDIT_AUTHORIZE) && !credential_present_modifier?(current)
        verdict, policy = pundit_verdict(current, action)
        case verdict
        when :refuses
          return {authz: "Pundit authorize", anonymous: nil}
        when :admits
          anonymous ||= policy
        else
          # An unresolved policy keeps the call's plain-form reading.
          return {authz: "Pundit authorize", anonymous: nil} if current.matches?(/\bauthorize\s+@?\w+/)
        end
      end
      ACTION_AUTH_PATTERNS.each do |pattern, desc|
        return {authz: desc, anonymous: nil} if current.matches?(pattern)
      end

      idx += 1
    end

    {authz: nil, anonymous: anonymous}
  end

  # `text` with its string literals emptied and a trailing comment dropped:
  # `flash[:notice] = "Please authorize the app"` calls nothing.
  private def code_only(text : String) : String
    text.gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, %("")).sub(/\s#(?!\{).*\z/, "")
  end

  # `authorize @venue, :index? if current_user`: runs only for a caller
  # who has the credential.
  private def credential_present_modifier?(code : String) : Bool
    return false unless m = code.match(CONDITION_MODIFIER)
    credential_present?(m[2], m[1] == "if", Hash(String, String).new, [] of String)
  end

  # Pundit `authorize @status, :show?` asks `StatusPolicy#show?`;
  # `authorize Article` asks the action's own query (`index?` for index).
  # The verdict reads the query's definition (and the policy's
  # initializer, up its parent policies): `:refuses` when a nil user gets
  # false (or an error), `:admits` when one passes (`true`, `return true
  # unless user`, `user.nil? || ...`),
  # `:unknown` when the policy or query cannot be found.
  # ponytail: the policy is the call's `policy_class:`, else found by
  # convention (`@status` / `Status` / `:status` →
  # `policies/status_policy.rb`); a record held in a method is unknown.
  PUNDIT_ARGS = /(?<![.\w])authorize\s*\(?\s*([:@]?\w+|[A-Z][\w:]*)(?:\s*,\s*:(\w+[?!]?))?/
  # A Pundit `authorize` call: it raises `NotAuthorizedError` when the
  # policy query answers false.
  PUNDIT_AUTHORIZE = /(?<![.\w])authorize(?:\s*\(|\s+(?=[:@A-Za-z_]))/
  # A query body line that lets a nil user pass.
  NIL_USER          = /@?(?:current_)?(?:user|account)/
  NIL_ADMITS        = /\A(?:return\s+true\s+unless\s+#{NIL_USER}\s*\z|return\s+true\s+if\s+(?:!\s*#{NIL_USER}\s*|#{NIL_USER}\.(?:nil|blank)\?\s*)\z)|(?:#{NIL_USER}\.(?:nil|blank)\?|!\s*#{NIL_USER}(?![\w.&?])|!\s*user_signed_in\?)\s*(?:\|\||\bor\b|\z)/
  NIL_RAISES        = /\braise\b.*\s(?:unless\s+#{NIL_USER}\s*\z|if\s+(?:!\s*#{NIL_USER}|#{NIL_USER}\.(?:nil|blank)\?)\s*\z)/
  USER_PRESENT_EXIT = /\Areturn\b.*\sif\s+#{NIL_USER}(?:\.present\?)?\s*\z/

  private def pundit_verdict(line : String, action : String?) : {Symbol, String?}
    return {:unknown, nil} unless m = line.match(PUNDIT_ARGS)
    record = m[1]
    query = m[2]? || action.try { |name| "#{name}?" }
    policy = line.match(/\bpolicy_class:\s*([A-Z][\w:]*)/).try(&.[1])
    policy ||= "#{record.lchop('@').lchop(':').camelcase}Policy" if record[0].in?('@', ':') || record[0].ascii_uppercase?
    return {:unknown, nil} unless query && policy
    label = "#{policy}##{query}"
    {@pundit_verdicts.put_if_absent(label) { policy_verdict(policy, query, 0) }, label}
  end

  private def policy_verdict(policy : String, query : String, depth : Int32) : Symbol
    return :refuses if policy_raises_for_nil?(policy, "initialize", false, Set(String).new)
    return :unknown unless body = policy_def(policy, query, false)
    joined = body.join(" ").strip
    return :admits if joined == "true"
    return :refuses if joined == "false" || joined.empty?
    return :admits if body.any?(&.matches?(NIL_ADMITS))
    if (other = joined.match(/\A(\w+\?)\z/)) && depth < 3
      # A query that delegates (`email_registrable?`, a `delegate`d
      # `staff?` we cannot read) answers what the other one does.
      verdict = policy_verdict(policy, other[1], depth + 1)
      return verdict == :unknown ? :refuses : verdict
    end
    # A check on the caller (`role.can?(:manage_users)`, `user.admin?`) a
    # nil one fails; one that never reads the caller (`record.published?`,
    # a registration setting) lets it through.
    joined.gsub(/(?<![\w:]):\w+/, "").matches?(CALLER_REF) ? :refuses : :admits
  end

  # A policy's reference to the caller it was built with.
  CALLER_REF = /(?<![\w.:])@?(?:user|current_user|current_account|account|account_user|user_context|pundit_user|role)\b(?!\s*:(?!:))/

  # Whether `name` (an instance or `self.` method of `policy` or the policies
  # it inherits from) raises for a nil user: `raise ... unless user`, a
  # `raise` after `return true if user`, or a call to a method that does.
  private def policy_raises_for_nil?(policy : String, name : String, singleton : Bool, visited : Set(String)) : Bool
    return false unless visited.add?("#{singleton}#{name}") && visited.size < 12
    return false unless body = policy_def(policy, name, singleton)
    exited = false
    body.each do |text|
      return true if text.matches?(NIL_RAISES) || (exited && text.matches?(/\Araise\b/))
      exited ||= text.matches?(USER_PRESENT_EXIT)
      text.scan(/(?<![\w.@:])(self\.class\.|self\.)?([a-z_]\w*[!?]?)/) do |call|
        next if call[2] == name || {"raise", "return", "if", "unless", "true", "false", "nil", "super"}.includes?(call[2])
        return true if policy_raises_for_nil?(policy, call[2], !call[1]?.nil?, visited)
      end
    end
    false
  end

  # The body lines (code only) of `def name` / `def self.name` in `policy`'s
  # file, else in the policies it inherits from.
  private def policy_def(policy : String, name : String, singleton : Bool, depth : Int32 = 0) : Array(String)?
    return if depth > 5
    suffix = "/policies/#{policy.underscore.gsub("::", "/")}.rb"
    return unless lines = collect_files_by_extension(".rb").find(&.ends_with?(suffix)).try { |path| read_file_lines(path) }
    head = singleton ? "self\\.#{Regex.escape(name)}" : Regex.escape(name)
    if def_idx = lines.index(&.matches?(/\A\s*def\s+#{head}(?![\w?!])/))
      indent = line_indent(lines[def_idx])
      return lines[(def_idx + 1)..].take_while { |source| source.strip.empty? || line_indent(source) > indent }
        .map { |source| code_only(source.strip) }.reject(&.empty?)
    end
    parent = lines.compact_map { |source| source.match(/\A\s*class\s+[\w:]+\s*<\s*([A-Z][\w:]*)/).try(&.[1]) }.first?
    parent.try { |name_of_parent| policy_def(name_of_parent, name, singleton, depth + 1) }
  end

  # A CanCanCan `authorize_resource` / `load_and_authorize_resource` in
  # `leaf`'s chain that runs `authorize!(action, resource)` for `action`,
  # when the ability `current_ability` builds grants that action on that
  # resource to no nil user: CanCan raises `AccessDenied`, which the app
  # answers with a refusal (or a 500). nil when an ability rule may admit
  # an anonymous caller, or the ability cannot be read. `url_params` are
  # the route's keys: `load_and_authorize_resource` checks a loaded record
  # only when the route carries its id.
  private def cancan_refuses(leaf : Noir::RailsCallbackChain::Klass, action : String?, url_params : Array(String)) : String?
    return unless action
    resolved = rails_chain.resolve(leaf, action)
    return if resolved.cancan.empty?
    abilities = cancan_ability_classes(resolved.paths)
    readers = abilities.compact_map { |name| cancan_ability(name, leaf.path) }
    return if readers.empty? || readers.size != abilities.size
    controller = leaf.name.split("::").last.underscore.rchop("_controller")
    resolved.cancan.each do |line|
      subject, query, id_key = cancan_target(line, controller, action)
      instance = line.starts_with?("load_and_authorize_resource") && !id_key.nil? && url_params.includes?(id_key)
      verdict = @cancan_verdicts.put_if_absent({leaf.path, line, action, instance}) do
        readers.all?(&.verdict(query, subject, instance).no?)
      end
      next unless verdict
      macro_name = line[/\A\w+/]
      return "CanCanCan #{macro_name} (#{abilities.join(", ")} grants :#{query} on #{subject} to no nil user)"
    end
    nil
  end

  # The subject and the action `authorize!` is called with, and the route
  # key of the record `load_and_authorize_resource` loads (nil when it
  # builds a new one or loads a collection): the resource class named by
  # the macro (`:class => Trace`), a symbol when `:class => false` /
  # `:class => :profile`, else the controller's model. A macro naming
  # another resource (`authorize_resource :changeset` in
  # `DownloadsController`) authorizes its parent, with `:show`.
  private def cancan_target(line : String, controller : String, action : String) : {String, String, String?}
    name = line.match(/\A\w+\s*\(?\s*:(\w+)\b(?!\s*=>)/).try(&.[1])
    klass = line.match(/(?:\bclass:|:class\s*=>)\s*(false\b|:\w+|["']?[A-Z][\w:]*)/).try(&.[1].delete("\"'"))
    singular = Noir::RubyInflector.singularize(controller)
    subject = klass == "false" ? ":#{name || singular}" : klass || (name || singular).camelcase
    parent = if m = line.match(/(?:\bparent:|:parent\s*=>)\s*(true|false)\b/)
               m[1] == "true"
             else
               !name.nil? && name != singular && name != controller
             end
    return {subject, "show", "#{name || singular}_id"} if parent
    id_key = line.match(/(?:\bid_param:|:id_param\s*=>)\s*:(\w+)/).try(&.[1]) || "id"
    {subject, action, action.in?("index", "new", "create") ? nil : id_key}
  end

  # The ability classes the controller's `current_ability` builds
  # (`ApiAbility.new(user, scopes)`), else CanCan's default `Ability`.
  private def cancan_ability_classes(paths : Array(String)) : Array(String)
    defs = (rails_chain.defs["current_ability"]? || [] of {String, Int32}).select { |path, _| paths.includes?(path) }
    return ["Ability"] if defs.empty?
    # Nearest class first: the override Ruby calls.
    nearest = defs.min_by { |path, _| paths.index(path) || paths.size }
    def_bodies("current_ability", [nearest]).flat_map(&.flat_map { |_, text| text.scan(/\b([A-Z][\w:]*)\.new\b/).map(&.[1]) }).uniq!
  end

  # The ability class `name` of the app the controller at `controller_path`
  # belongs to: its file by Rails naming under that app's `app/` (a spec
  # helper or another engine's class of the same name is not it). nil when
  # there is none, or more than one.
  private def cancan_ability(name : String, controller_path : String) : Noir::CanCanAbility?
    return unless idx = controller_path.rindex("/app/controllers/")
    app = controller_path[0, idx + "/app/".size]
    @cancan_abilities.put_if_absent({name, app}) do
      suffix = "/#{name.underscore.gsub("::", "/")}.rb"
      found = collect_files_by_extension(".rb").select do |path|
        path.starts_with?(app) && path.ends_with?(suffix) && !path[app.size..].matches?(%r{(?:\A|/)(?:spec|test)s?/}) &&
          read_file_lines(path).try(&.any?(&.matches?(/\A\s*include\s+CanCan::Ability\b/)))
      end
      next unless found.size == 1 && (lines = read_file_lines(found.first))
      ability = Noir::CanCanAbility.new(lines)
      ability if ability.readable?
    end
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
