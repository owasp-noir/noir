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
    {/\bauthorize\s+@?\w+/, "Pundit authorize"},
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
    @anonymous_queries = Hash(String, Bool).new
    @rejecting_defs = Hash(String, Bool).new
    @denying_helpers = Hash(String, Bool).new
    @denies_anonymous = Hash(String, Bool).new
    @deny_settings = Hash(String, String).new
    @caller_ivars = Hash(String, Array(String)).new
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
      # controller's chain, not with the one of the file it is written in.
      dispatch = endpoint.handler.try(&.dispatch_path).try { |dispatch_path| rails_chain.controller_in(dispatch_path) } if endpoint.handler.try(&.path) == path
      chain = (dispatch || rails_chain.controller_in(path)).try { |leaf| rails_chain.resolve(leaf, action) }
      controller = check_controller_auth(lines, line_idx, flags, jumps, chain)
      authz_desc = controller[:authz]
      # skip_before_action only suppresses authentication callbacks — not
      # independent authorize / CanCanCan checks in the action body.
      unless controller[:skipped]
        authn_desc = controller[:authn]
        leaf = dispatch || controller[:class_idx].try { |class_idx| rails_chain.classes[{path, class_idx}]? }
        if leaf && (dispatch || leaf.parent) && (authn_desc.nil? || setting_lifted?(authn_desc) || authz_desc.nil?)
          inherited = chain_guards(leaf, action)
          authn_desc = stronger(authn_desc, inherited[:authn])
          authz_desc ||= inherited[:authz]
        end
      end

      # Action-body authorization (Pundit/CanCanCan) stacks with controller authn.
      body = check_action_body_auth(lines, line_idx)
      authz_desc ||= body[:authz]

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
      return if authn_desc || authz_desc || body[:anonymous] || controller[:skipped] || controller[:opted_out]

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

  private def check_controller_auth(lines : Array(String), action_line : Int32, flags : Array(UInt8), jumps : Array(Int32), chain : Noir::RailsCallbackChain::Resolution?) : NamedTuple(authn: String?, authz: String?, skipped: Bool, opted_out: Bool, class_idx: Int32?)
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
          next if skipped_callbacks.includes?(callback)
          authn_desc = stronger(authn_desc, callback_guard(callback, chain)) unless skipped
          authz_desc ||= callback_authz(callback)
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
      next if resolved.conditional.includes?(callback)
      authn = stronger(authn, callback_guard(callback, resolved))
      authz ||= callback_authz(callback)
    end
    {authn: authn, authz: authz}
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
  CALLBACK_REJECTS = /\b(?:head\s+(?::unauthorized|:forbidden|401|403)|status:\s*(?::unauthorized|:forbidden|401|403)|redirect_to|redirect_back|raise|throw|halt|authenticate_or_request_with_http_\w+|request_http_\w+_authentication)\b|\w*auth\w*!/
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
    key = "#{callback}|#{ivars.join(',')}"
    return @callback_guards[key] if @callback_guards.has_key?(key)
    desc = BEFORE_ACTION_AUTHN_PATTERNS.find { |pattern, _| "before_action :#{callback}".matches?(pattern) }.try(&.[1])
    if desc
      if rails_chain.defs.has_key?(callback)
        desc = body_rejects?(callback, Set(String).new) ? "#{callback} (app-defined, rejects in its body)" : nil
      elsif !library_guard_rejects?(callback)
        desc = nil
      end
    elsif rails_chain.defs.has_key?(callback) && denies_anonymous?(callback, ivars)
      desc = if setting = @deny_settings["#{callback}|#{ivars.join(',')}"]?
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
  private def callback_authz(callback : String) : String?
    return @callback_authz[callback] if @callback_authz.has_key?(callback)
    desc = BEFORE_ACTION_AUTHZ_PATTERNS.find { |pattern, _| "before_action :#{callback}".matches?(pattern) }.try(&.[1])
    desc = nil if desc && rails_chain.defs.has_key?(callback) && !body_rejects?(callback, Set(String).new)
    @callback_authz[callback] = desc
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
                  (text.matches?(PUNDIT_AUTHORIZE) && !anonymous_policy(text)) ||
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
  DENY_RESPONSE = /\bhead\s*\(?\s*(?::unauthorized|:forbidden|401|403)\b|\bstatus:\s*(?::unauthorized\b|:forbidden\b|40[13]\b)/
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
  private def denies_anonymous?(name : String, ivars : Array(String), visited : Set(String) = Set(String).new) : Bool
    top = visited.empty?
    key = "#{name}|#{ivars.join(',')}"
    return @denies_anonymous[key] if top && @denies_anonymous.has_key?(key)
    return false unless visited.add?(name)
    # The setting each deny also waits on; nil for a deny none decides.
    settings = [] of String?
    def_bodies(name).each do |body|
      break unless settings.empty? || (top && settings.all?)
      assigns = Hash(String, String).new
      body.each { |_, text| (m = text.match(/^(@?\w+)\s*\|{0,2}=(?!=)\s*(.+)/)) && (assigns[m[1]] = m[2]) }
      body.each_with_index do |(_, text), i|
        strict = text.matches?(DENY_RESPONSE) || text.scan(/\b[a-z_]\w*[!?]?/).any? { |m| always_denies?(m[0]) } ||
                 text.scan(BARE_CALL).any? { |m| m[0] != name && rails_chain.defs.has_key?(m[0]) && denies_anonymous?(m[0], ivars, visited) }
        next unless strict || text.matches?(SOFT_DENY)
        next if credential_gated?(body, i) || text.matches?(CREDENTIAL_PRESENT_MODIFIER)
        next unless conditions = deny_conditions(body, i)
        parts = deny_parts(conditions)
        next if parts.any? { |c, when_true| credential_present?(c, when_true, assigns, ivars) }
        # `return if params[:page].to_i <= 1000` above the 401: a request
        # value that is no credential, so the caller picks whether it fires.
        next if parts.any? { |c, _| c.matches?(/(?<![\w.@])params\b/) && !credential_condition?(c, assigns, ivars) }
        next unless (strict && parts.empty?) || parts.any? { |c, when_true| credential_absent?(c, when_true, assigns, ivars) }
        settings << parts.find { |c, _| app_setting?(c) }.try(&.[0].lchop('!').strip)
        # Past the first deny only a top-level read looks on, for one no
        # setting decides.
        break unless top && settings.last
      end
    end
    result = !settings.empty?
    if top
      @denies_anonymous[key] = result
      first = settings.first?
      @deny_settings[key] = first if first && settings.none?(Nil)
    end
    result
  end

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
  SOFT_DENY = /\bredirect_(?:to|back(?:_or_to)?)\b|\bhead\s*\(?\s*(?::bad_request|:not_found|4\d\d)\b|\bstatus:\s*(?::bad_request\b|:not_found\b|4\d\d\b)/

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
      return true unless ((j + 1)...i).any? { |k| body[k][0] == indent && body[k][1].matches?(/^els(?:e|if)\b/) }
    end
    false
  end

  private def check_action_body_auth(lines : Array(String), action_line : Int32) : NamedTuple(authz: String?, anonymous: String?)
    # Scan forward from the action definition for auth calls
    idx = action_line + 1
    end_idx = [action_line + 20, lines.size - 1].min
    anonymous : String? = nil

    while idx <= end_idx
      current = lines[idx].strip
      # Stop at next method definition
      break if current.starts_with?("def ") && idx > action_line

      ACTION_AUTH_PATTERNS.each do |pattern, desc|
        next unless current.matches?(pattern)
        if policy = anonymous_policy(current)
          anonymous ||= policy
        else
          return {authz: desc, anonymous: nil}
        end
      end

      idx += 1
    end

    {authz: nil, anonymous: anonymous}
  end

  # Pundit `authorize @status, :show?` asks `StatusPolicy#show?`. A query
  # that answers true for a nil caller (`current_account.nil? || ...`) is a
  # visibility rule anonymous requests pass, not a check on who calls.
  # ponytail: the policy is the call's `policy_class:`, else found by Rails
  # convention (`@status` / `Status` → `policies/status_policy.rb`); a record
  # named otherwise keeps its tag.
  PUNDIT_CALL = /\bauthorize\s*\(?\s*(@\w+|[A-Z][\w:]*|[a-z_]\w*)\s*,\s*:(\w+\?)/
  # A Pundit `authorize` call: it raises `NotAuthorizedError` when the
  # policy query answers false.
  PUNDIT_AUTHORIZE = /(?<![.\w])authorize(?:\s*\(|\s+(?=[@A-Za-z_]))/
  ANONYMOUS_ADMITS = /\b(?:current_account|current_user|user|account)\.nil\?|!\s*user_signed_in\?/

  # `StatusPolicy#show?` when the Pundit call on `line` asks a query that
  # admits a nil caller, nil otherwise.
  private def anonymous_policy(line : String) : String?
    return unless m = line.match(PUNDIT_CALL)
    policy = line.match(/\bpolicy_class:\s*([A-Z][\w:]*)/).try(&.[1]) || "#{m[1].lchop('@').camelcase}Policy"
    label = "#{policy}##{m[2]}"
    admits = @anonymous_queries.put_if_absent(label) do
      suffix = "/policies/#{policy.underscore.gsub("::", "/")}.rb"
      lines = collect_files_by_extension(".rb").find(&.ends_with?(suffix)).try { |path| read_file_lines(path) } || [] of String
      next false unless def_idx = lines.index(&.strip.starts_with?("def #{m[2]}"))
      body = lines[(def_idx + 1)..].take_while { |source| source.strip.empty? || line_indent(source) > line_indent(lines[def_idx]) }
      body.any?(&.matches?(ANONYMOUS_ADMITS))
    end
    label if admits
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
