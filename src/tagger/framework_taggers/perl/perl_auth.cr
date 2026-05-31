require "../../../models/framework_tagger"
require "../../../models/endpoint"

# Identifies authentication / authorization guards in Perl web apps.
#
# Dancer2 leans on Dancer2::Plugin::Auth::Extensible, which guards routes
# either inline on the declaration:
#
#   get '/admin' => require_role Admin => sub { ... };
#   get '/me'    => require_login sub { ... };
#
# or globally through a `hook before` that calls `logged_in_user` /
# `redirect`. Catalyst and Mojolicious use handler-body checks
# (`$c->user_exists`, `$c->assert_user_roles`, `$c->require_login`,
# `$self->is_user_authenticated`). This tagger surfaces all of them as a
# single `auth` tag so reviewers can spot the unprotected routes.
class PerlAuthTagger < FrameworkTagger
  # Inline route wrappers from Dancer2::Plugin::Auth::Extensible. These
  # sit between the path and the `sub { ... }` on the route declaration.
  ROUTE_WRAPPER_PATTERNS = [
    {/\brequire_all_roles\b/, "Dancer2 require_all_roles"},
    {/\brequire_any_role\b/, "Dancer2 require_any_role"},
    {/\brequire_role\b/, "Dancer2 require_role"},
    {/\brequire_login\b/, "Dancer2 require_login"},
  ]

  # Checks that appear inside the handler body (or a nearby helper).
  BODY_PATTERNS = [
    {/\blogged_in_user\b/, "Dancer2 logged_in_user"},
    {/\buser_has_role\b/, "Dancer2 user_has_role"},
    {/\bauthenticate_user\b/, "Dancer2 authenticate_user"},
    {/->\s*assert_user_roles\b/, "Catalyst assert_user_roles"},
    {/->\s*check_user_roles\b/, "Catalyst check_user_roles"},
    {/->\s*user_exists\b/, "Catalyst user_exists"},
    {/\$c\s*->\s*require_login\b/, "Catalyst require_login"},
    {/\$c\s*->\s*authenticate\b/, "Catalyst authenticate"},
    {/->\s*is_user_authenticated\b/, "Mojolicious is_user_authenticated"},
  ]

  # Keywords that make a `hook before` / Catalyst `sub auto` block an
  # application-wide guard covering every route in the file.
  GLOBAL_GUARD_KEYWORDS = /\brequire_login\b|\brequire_role\b|\blogged_in_user\b|\buser_has_role\b|->\s*authenticate\b|->\s*user_exists\b|->\s*require_login\b|redirect\b.*\blogin\b/

  GLOBAL_GUARD_BLOCK_START = /\bhook\s+before\b|\bbefore\s*=>\s*sub\b|\bsub\s+auto\b|\bsub\s+begin\b/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "perl_auth"
  end

  def self.target_techs : Array(String)
    ["perl_dancer2", "perl_mojolicious", "perl_catalyst"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each { |endpoint| check_endpoint(endpoint) }
    endpoints
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      next if line_num < 1 || line_num > lines.size
      idx = line_num - 1

      description = check_route_wrapper(lines, idx) ||
                    check_handler_body(lines, idx) ||
                    check_global_guard(lines)
      next if description.nil?

      endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "perl_auth"))
      return
    end
  end

  # Scan the route declaration (which may wrap across a few lines) up to
  # the `sub` keyword for an inline Auth::Extensible wrapper.
  private def check_route_wrapper(lines : Array(String), idx : Int32) : String?
    decl = String.build do |io|
      j = idx
      limit = [idx + 4, lines.size - 1].min
      while j <= limit
        io << lines[j] << ' '
        # Stop at the handler body (`sub`) or end of statement. Match `sub`
        # as a keyword, not a substring, so paths like `/subscription`
        # don't end the scan before a wrapper on the following line.
        break if lines[j].matches?(/\bsub\b/) || lines[j].includes?(';')
        j += 1
      end
    end

    ROUTE_WRAPPER_PATTERNS.each do |pattern, desc|
      return desc if decl.matches?(pattern)
    end
    nil
  end

  # Scan forward from the route into the handler body for an inline
  # authentication / authorization check.
  private def check_handler_body(lines : Array(String), idx : Int32) : String?
    start_idx = idx
    end_idx = [idx + 20, lines.size - 1].min

    (start_idx..end_idx).each do |i|
      current = lines[i]
      # Stop if we fall into the next route/sub declaration.
      break if i > idx && current.matches?(/^\s*(?:get|post|put|patch|options|del|any|prefix)\s/)

      BODY_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end
    nil
  end

  # An application-wide `hook before { ... }` (Dancer2) or `sub auto`
  # (Catalyst) that performs an auth check protects every route in the
  # file.
  private def check_global_guard(lines : Array(String)) : String?
    lines.each_with_index do |line, idx|
      next unless line.matches?(GLOBAL_GUARD_BLOCK_START)

      end_idx = [idx + 15, lines.size - 1].min
      (idx..end_idx).each do |i|
        if lines[i].matches?(GLOBAL_GUARD_KEYWORDS)
          return global_guard_description(line)
        end
      end
    end
    nil
  end

  # Name the guard after the block that introduced it: Catalyst uses
  # `sub auto` / `sub begin`, Dancer2 uses `hook before` / `before => sub`.
  private def global_guard_description(block_start : String) : String
    if block_start.matches?(/\bsub\s+auto\b|\bsub\s+begin\b/)
      "Catalyst auto/begin guard"
    else
      "Dancer2 hook before guard"
    end
  end
end
