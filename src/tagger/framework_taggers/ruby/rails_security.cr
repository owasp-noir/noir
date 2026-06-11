require "../../../models/framework_tagger"
require "../../../models/endpoint"

# Rails-specific security tagger.
#
# `ruby_auth` already classifies authentication (Devise/Pundit/CanCanCan/…),
# so this tagger covers the other Rails controller-level security signals
# that map cleanly onto an action and are *deviations from the framework
# default* — i.e. worth a reviewer's attention rather than ambient noise:
#
#   * csrf-protection — CSRF disabled (`skip_before_action
#     :verify_authenticity_token`, `skip_forgery_protection`) or downgraded
#     (`protect_from_forgery with: :null_session`). Rails protects every
#     state-changing request by default, so an explicit opt-out is the
#     interesting case.
#   * mass-assignment — Strong Parameters bypassed (`params.permit!`,
#     `params.to_unsafe_h`, or a raw `params[:x]` hash handed to a model
#     writer like `Model.new(params[:user])`).
#   * rate-limit — Rails 8 native `rate_limit` throttle on the action.
#
# Like `ruby_auth`, detection is single-file and line-based: it walks the
# controller the action lives in. Cross-file concerns (a `null_session`
# base controller inherited by children, a Rack::Attack initializer) are
# out of scope by design — those live outside the action's own file.
class RailsSecurityTagger < FrameworkTagger
  # Class-level macros that turn CSRF verification OFF for (some) actions.
  CSRF_DISABLE_PATTERNS = [
    {/skip_before_action\s+:verify_authenticity_token/, "verify_authenticity_token skipped"},
    {/skip_forgery_protection/, "skip_forgery_protection"},
  ]

  # `protect_from_forgery with: :null_session` keeps the filter but lets a
  # forged request through with a blank session instead of rejecting it —
  # the usual choice for token/API controllers, and worth flagging because
  # cookie-session callers lose CSRF rejection.
  CSRF_NULL_SESSION_PATTERN = /protect_from_forgery\s+.*with:\s*:null_session/

  # Rails 8 `rate_limit to: N, within: T[, only:/except:]` declared like a
  # before_action at class scope.
  RATE_LIMIT_PATTERN = /\brate_limit\s+(?:to|within|by|with|store|name|only|except):/

  # Strong-Parameters escape hatches in an action body.
  MASS_ASSIGN_BANG_PATTERNS = [
    {/params\.permit!/, "params.permit!"},
    {/params\.to_unsafe_h(?:ash)?\b/, "params.to_unsafe_h"},
  ]

  # A raw `params[:x]` hash passed straight into a model writer (no
  # intervening `.permit`). `find`/`where` take a scalar id, so they are
  # deliberately excluded — only attribute-setting writers are risky.
  MASS_ASSIGN_WRITER_PATTERN =
    /\.(?:new|create|create!|update|update!|update_attributes|update_attributes!|assign_attributes)\s*\(\s*params\[/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "rails_security"
  end

  def self.target_techs : Array(String)
    ["ruby_rails"]
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
      # Skip stale/out-of-range line refs: a line beyond the content we read
      # would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      action_name = extract_action_name(lines, line_idx)

      # Each concern is independent — an action can be CSRF-disabled AND
      # rate-limited AND mass-assigning — so collect all that apply rather
      # than returning on the first hit.
      if desc = check_csrf(lines, line_idx, action_name)
        endpoint.add_tag(Tag.new("csrf-protection", desc, "rails_security"))
      end

      if desc = check_rate_limit(lines, line_idx, action_name)
        endpoint.add_tag(Tag.new("rate-limit", desc, "rails_security"))
      end

      if desc = check_mass_assignment(lines, line_idx)
        endpoint.add_tag(Tag.new("mass-assignment", desc, "rails_security"))
      end
    end
  end

  # Walk backwards from the action to its enclosing class, looking for a
  # CSRF disable/downgrade macro. The nearest matching macro wins.
  private def check_csrf(lines : Array(String), action_line : Int32, action_name : String?) : String?
    idx = action_line
    while idx >= 0
      current = lines[idx].strip

      CSRF_DISABLE_PATTERNS.each do |pattern, label|
        if current.matches?(pattern) && macro_applies?(current, action_name)
          return "CSRF protection disabled (#{label}) — state-changing requests to this action are not CSRF-validated."
        end
      end

      if current.matches?(CSRF_NULL_SESSION_PATTERN) && macro_applies?(current, action_name)
        return "CSRF protection downgraded to null_session — forged requests proceed with an empty session instead of being rejected (typical for token/API controllers)."
      end

      break if current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  # Rails 8 `rate_limit` is a class-level macro like before_action; walk
  # back to the class and honour only:/except:.
  private def check_rate_limit(lines : Array(String), action_line : Int32, action_name : String?) : String?
    idx = action_line
    while idx >= 0
      current = lines[idx].strip

      if current.matches?(RATE_LIMIT_PATTERN) && macro_applies?(current, action_name)
        return "Rate limited by Rails rate_limit — request volume to this action is throttled per client."
      end

      break if current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  # Scan the action body forward for Strong-Parameters bypasses.
  private def check_mass_assignment(lines : Array(String), action_line : Int32) : String?
    idx = action_line + 1
    end_idx = [action_line + 25, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx].strip
      # Stop at the next method definition (left the action body).
      break if current.starts_with?("def ") && idx > action_line

      MASS_ASSIGN_BANG_PATTERNS.each do |pattern, label|
        if current.matches?(pattern)
          return "Mass assignment risk — Strong Parameters bypassed via #{label}, allowing arbitrary model attributes to be set."
        end
      end

      if current.matches?(MASS_ASSIGN_WRITER_PATTERN)
        return "Mass assignment risk — a raw params hash is passed to a model writer without Strong Parameters filtering."
      end

      idx += 1
    end

    nil
  end

  private def extract_action_name(lines : Array(String), line_idx : Int32) : String?
    return if line_idx < 0 || line_idx >= lines.size
    match = lines[line_idx].strip.match(/def\s+(\w+)/)
    match ? match[1] : nil
  end

  # A class-level macro with `only:`/`except:` filters applies to the action
  # only if the action is (only:) / is not (except:) named in the filter.
  # With no filter it applies to every action. An unknown action name is
  # treated conservatively: skip for only:, keep for except:.
  private def macro_applies?(line : String, action_name : String?) : Bool
    if line.includes?("only:")
      action_in_filter?(line, action_name)
    elsif line.includes?("except:")
      !action_in_filter?(line, action_name)
    else
      true
    end
  end

  # Detect the action across the symbol/string/`%i[]`/`%w[]` filter forms:
  #   only: :create | only: [:create, :update] | only: %i[create update]
  #   except: "create" | except: ["create"]
  # Memoized per action name — this runs per macro line per action, and
  # an interpolated literal would recompile the pattern on every check.
  @action_token_regexes = Hash(String, Regex).new

  private def action_in_filter?(line : String, action_name : String?) : Bool
    return false if action_name.nil?
    # Whole-token match (symbol/quote prefix + delimiter) so action `create`
    # is NOT matched by `:create_comment` / `except: [:show_all]`.
    action_re = @action_token_regexes[action_name] ||= /(?::|"|')#{Regex.escape(action_name)}(?:"|'|,|\s|\]|\)|$)/
    return true if line.matches?(action_re)
    if m = line.match(/%[iIwW]\[([^\]]*)\]/)
      return m[1].split.includes?(action_name)
    end
    false
  end
end
