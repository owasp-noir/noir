require "../../../models/framework_tagger"
require "../../../models/endpoint"

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

  # Class-body lines that change the callback chain a subclass inherits.
  RAILS_CALLBACK_LINE = /^(?:include|(?:prepend_|skip_)?before_action|allow_unauthenticated_access)\b/

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

  def initialize(options : Hash(String, YAML::Any))
    super
    @controller_line_flags = Hash(String, Array(UInt8)).new
    @rails_indexed = false
    @rails_classes = Hash({String, Int32}, RailsClass).new
    @rails_by_name = Hash(String, Array(RailsClass)).new
  end

  # A Ruby class or module under a `controllers` directory, with the
  # class-body lines that touch the callback chain (`RAILS_CALLBACK_LINE`).
  record RailsClass, name : String, namespace : String, parent : String?, callbacks : Array(String) = [] of String

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

      authn_desc : String? = nil

      # Rails/Hanami: collect controller before_action authn *and* authz.
      # Returning after the first match used to drop Devise when a closer
      # `before_action :authorize` won the walk, and skipped body authorize.
      controller = check_controller_auth(lines, line_idx, controller_line_flags(path_info.path, lines))
      # skip_before_action only suppresses authentication callbacks — not
      # independent authorize / CanCanCan checks in the action body.
      unless controller[:skipped]
        authn_desc = controller[:authn]
        if authn_desc.nil? && (class_idx = controller[:class_idx])
          authn_desc = inherited_authn(path_info.path, class_idx, extract_action_name(lines, line_idx))
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

      # Check Sinatra/Rack patterns in context
      description = check_sinatra_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ruby_auth"))
        return
      end

      # Check Grape patterns (before blocks, http_basic, etc.)
      description = check_grape_auth(lines, line_idx)
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
    if only = callback_option(current, ONLY_OPTION)
      return !!(action_name && only.includes?(action_name))
    end
    if except = callback_option(current, EXCEPT_OPTION)
      return !(action_name && except.includes?(action_name))
    end
    true
  end

  ONLY_OPTION   = /\bonly:/
  EXCEPT_OPTION = /\bexcept:/

  # The action names an `only:` / `except:` option lists, in any of its
  # spellings: `:show`, `[:show, :edit]`, `%i[show edit]`, `"show"`.
  # Matching `":#{action}"` against the raw line missed the `%i[ new create ]`
  # the Rails generators write, and let `:new` match `:new_session`.
  private def callback_option(line : String, option : Regex) : Array(String)?
    match = line.match(option)
    return unless match
    value = line[match.end..]
    if stop = value.index(/\b\w+:(?!:)/)
      value = value[0, stop]
    end
    value.gsub(/%[iwIW][\[(]/, " ").scan(/\w+[?!]?/).map(&.[0])
  end

  private def check_controller_auth(lines : Array(String), action_line : Int32, flags : Array(UInt8)) : NamedTuple(authn: String?, authz: String?, skipped: Bool, opted_out: Bool, class_idx: Int32?)
    # Walk backwards to find the controller class and before_action declarations
    idx = action_line
    action_name = extract_action_name(lines, action_line)
    authn_desc : String? = nil
    authz_desc : String? = nil
    skipped = false
    skipped_callbacks = Set(String).new
    class_idx : Int32? = nil

    while idx >= 0
      unless flags[idx] == CONTROLLER_AUTH_LINE
        if flags[idx] == CLASS_LINE
          class_idx = idx
          break
        end
        idx -= 1
        next
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

      unless skipped
        BEFORE_ACTION_AUTHN_PATTERNS.each do |pattern, desc|
          if registered.matches?(pattern) && applies_to_action?(current, action_name)
            authn_desc ||= desc
          end
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

  # A controller's own class body is only half its callback chain: Devise's
  # `before_action :authenticate_user!` usually sits in ApplicationController,
  # and `rails generate authentication` (Rails 8) installs
  # `before_action :require_authentication` through an `Authentication`
  # concern ApplicationController includes, so every controller is
  # authenticated unless it opts out. Resolve what the parent chain leaves
  # active for `action`, honouring `skip_before_action` /
  # `allow_unauthenticated_access` and their `only:` / `except:` lists.
  private def inherited_authn(path : String, class_idx : Int32, action : String?) : String?
    index_rails_classes unless @rails_indexed
    leaf = @rails_classes[{path, class_idx}]?
    return unless leaf && leaf.parent
    active = Hash(String, String).new
    # The leaf's own callbacks run last, so its `skip_before_action` lines
    # remove what the parents registered.
    apply_ancestor(leaf, action, active, 0)
    active.first_value?
  end

  private def apply_ancestor(klass : RailsClass?, action : String?, active : Hash(String, String), depth : Int32)
    return unless klass && depth < 16
    if parent = klass.parent
      apply_ancestor(lookup_rails_class(parent, klass.namespace), action, active, depth + 1)
    end
    apply_callbacks(klass, action, active, depth)
  end

  private def apply_callbacks(klass : RailsClass, action : String?, active : Hash(String, String), depth : Int32)
    klass.callbacks.each do |line|
      if line.starts_with?("include")
        line.scan(/[A-Z][\w:]*/) do |m|
          if (mod = lookup_rails_class(m[0], klass.namespace)) && depth < 16
            apply_callbacks(mod, action, active, depth + 1)
          end
        end
      elsif line.starts_with?("allow_unauthenticated_access")
        active.delete("require_authentication") if applies_to_action?(line, action)
      elsif m = line.match(/^(skip_)?\w*before_action\s+((?::\w+[!?]?\s*,?\s*)+)/)
        next unless applies_to_action?(line, action)
        m[2].scan(/:(\w+[!?]?)/) do |name|
          callback = name[1]
          if m[1]?
            active.delete(callback)
          elsif desc = BEFORE_ACTION_AUTHN_PATTERNS.find { |pattern, _| "before_action :#{callback}".matches?(pattern) }
            active[callback] = desc[1]
          end
        end
      end
    end
  end

  # Ruby resolves a bare constant from the innermost namespace outwards. Two
  # definitions of one name (reopened, or the same name in two apps of a
  # monorepo) are ambiguous and resolve to nothing.
  private def lookup_rails_class(name : String, namespace : String) : RailsClass?
    name = name.lchop("::")
    scopes = namespace.split("::", remove_empty: true)
    scopes.size.downto(0) do |n|
      full = (scopes[0, n] + [name]).join("::")
      if found = @rails_by_name[full]?
        return found.size == 1 ? found.first : nil
      end
    end
    nil
  end

  # Every class and module under a `controllers` directory, with the
  # class-body lines that touch the callback chain. Lines inside a `def` are
  # not class-body: the `Authentication` concern's own
  # `def allow_unauthenticated_access` wraps a `skip_before_action` that
  # runs only when a controller calls it.
  private def index_rails_classes
    @rails_indexed = true
    collect_files_by_extension(".rb").each do |path|
      next unless base_relative_path(path).includes?("controllers")
      next unless lines = read_file_lines(path)
      stack = [] of {RailsClass, Int32}
      def_indent : Int32? = nil
      lines.each_with_index do |line, idx|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')
        indent = line.size - line.lstrip.size
        if open_def = def_indent
          def_indent = nil if indent <= open_def && stripped == "end"
          next
        end
        while (top = stack.last?) && top[1] >= indent
          stack.pop
        end
        if m = stripped.match(/^(?:class|module)\s+([A-Z][\w:]*)(?:\s*<\s*([\w:]+))?/)
          namespace = stack.last?.try(&.[0].name) || ""
          full = namespace.empty? ? m[1] : "#{namespace}::#{m[1]}"
          klass = RailsClass.new(full, namespace, m[2]?)
          @rails_classes[{path, idx}] = klass
          (@rails_by_name[full] ||= [] of RailsClass) << klass
          stack << {klass, indent}
        elsif stripped.matches?(/^def\s/)
          def_indent = indent unless stripped.matches?(/\bend$|^def\s+[\w.?!]+(?:\([^)]*\))?\s*=[^=]/)
        elsif (top = stack.last?) && stripped.matches?(RAILS_CALLBACK_LINE)
          top[0].callbacks << stripped
        end
      end
    end
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
    return if line_idx < 0 || line_idx >= lines.size
    line = lines[line_idx].strip
    match = line.match(/def\s+(\w+)/)
    match ? match[1] : nil
  end

  private def check_grape_auth(lines : Array(String), route_line : Int32) : String?
    # Grape uses before { } blocks, often near the top of the class or inside resource/namespace
    start_idx = [route_line - 20, 0].max

    (start_idx...route_line).each do |idx|
      current = lines[idx].strip

      GRAPE_AUTH_PATTERNS.each do |pattern, desc|
        if current.matches?(pattern)
          return desc
        end
      end
    end

    nil
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
