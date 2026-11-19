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
@[Noir::TaggerFor(key: "perl_auth", name: "Perl Auth Tagger", desc: "Identifies Perl authentication patterns (Dancer2 Auth::Extensible, Mojolicious, Catalyst)", order: 260)]
class PerlAuthTagger < FrameworkTagger
  # Inline route wrappers from Dancer2::Plugin::Auth::Extensible. These
  # sit between the path and the `sub { ... }` on the route declaration.
  ROUTE_WRAPPER_PATTERNS = [
    {/\brequire_all_roles\b/, "Dancer2 require_all_roles"},
    {/\brequire_any_role\b/, "Dancer2 require_any_role"},
    {/\brequire_role\b/, "Dancer2 require_role"},
    {/\brequire_login\b/, "Dancer2 require_login"},
  ]

  # Handler-body calls that refuse the caller themselves.
  REFUSING_BODY_PATTERNS = [
    {/->\s*assert_user_roles\b/, "Catalyst assert_user_roles"},
    {/\$c\s*->\s*require_login\b/, "Catalyst require_login"},
  ]

  # Handler-body calls that only read who the caller is, or log them in
  # (`authenticate_user`, `$c->authenticate` in a login action). They guard
  # the handler only when it also refuses (REFUSAL): a home page greeting
  # `logged_in_user` serves anonymous callers too.
  READING_BODY_PATTERNS = [
    {/\blogged_in_user\b/, "Dancer2 logged_in_user"},
    {/\buser_has_role\b/, "Dancer2 user_has_role"},
    {/\bauthenticate_user\b/, "Dancer2 authenticate_user"},
    {/->\s*check_user_roles\b/, "Catalyst check_user_roles"},
    {/->\s*user_exists\b/, "Catalyst user_exists"},
    {/\$c\s*->\s*authenticate\b/, "Catalyst authenticate"},
    {/->\s*is_user_authenticated\b/, "Mojolicious is_user_authenticated"},
  ]

  # A 401/403, a forbidden/denied page, or a redirect to the login page.
  REFUSAL = /(?<![\w.])40[13](?![\d.])|\bforbidden\b|\bdenied\b|\bunauthori[sz]ed\b|\bredirect\w*\b[^;]*\b(?:log[_-]?in|sign[_-]?in)\b/i

  # A statement that stops the request, conditioned on what follows its
  # `unless` / `if`: `halt(...) unless logged_in_user`, `return unless ...`,
  # `$c->detach('/error') unless $c->check_user_roles('admin')`.
  # `pass unless ...` hands the request on and is not one.
  CONDITIONED_REFUSAL = /\A\s*(?:return\s+)?(?:\$\w+\s*->\s*(?:\w+\s*->\s*)*)?(?:halt|detach|die|croak|not_found|redirect\w*|send_error|status|forward)\b[^;]*?\b(?:unless|if)\b(.*)|\A\s*return\s*(?:0|undef)?\s*\b(?:unless|if)\b(.*)/

  # Keywords that make a `hook before` / Catalyst `sub auto` block an
  # application-wide guard covering every route in the file.
  GLOBAL_GUARD_KEYWORDS = /\brequire_login\b|\brequire_role\b|\blogged_in_user\b|\buser_has_role\b|->\s*authenticate\b|->\s*user_exists\b|->\s*require_login\b|redirect\b.*\blogin\b/

  GLOBAL_GUARD_BLOCK_START = /\bhook\s+before\b|\bbefore\s*=>\s*sub\b|\bsub\s+auto\b|\bsub\s+begin\b/

  def initialize(options : Hash(String, YAML::Any))
    super
    @bridge_verdicts = Hash({String, String}, Bool).new
  end

  def self.target_techs : Array(String)
    ["perl_dancer2", "perl_mojolicious", "perl_catalyst"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      next if line_num < 1 || line_num > lines.size
      idx = line_num - 1

      description = check_route_wrapper(lines, idx) ||
                    check_handler_body(lines, idx) ||
                    check_lite_under(lines, idx) ||
                    check_mojo_bridge(lines, idx) ||
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
    end_idx = [idx + 20, lines.size - 1].min
    body = [] of String
    (idx..end_idx).each do |i|
      # Stop if we fall into the next route/sub declaration — or a
      # Mojolicious::Lite `under`, whose guard covers the routes after it.
      break if i > idx && lines[i].matches?(/^\s*(?:get|post|put|patch|options|del|any|prefix|under)\b/)
      body << lines[i]
    end

    body.each do |line|
      REFUSING_BODY_PATTERNS.each do |pattern, desc|
        return desc if line.matches?(pattern)
      end
    end
    return unless body.any? { |line| line.matches?(REFUSAL) || refusal_conditioned_on_read?(line) }
    body.each do |line|
      READING_BODY_PATTERNS.each do |pattern, desc|
        return desc if line.matches?(pattern)
      end
    end
    nil
  end

  private def refusal_conditioned_on_read?(line : String) : Bool
    return false unless m = line.match(CONDITIONED_REFUSAL)
    condition = m[1]? || m[2]? || ""
    READING_BODY_PATTERNS.any? { |pattern, _| condition.matches?(pattern) }
  end

  # Mojolicious::Lite `under sub { ... }`: every route declared after it
  # (up to the next `under`) runs behind its callback, so the nearest
  # `under` above the route decides.
  # ponytail: file-order only; an `under` scoped inside a `group { }` block
  # leaks to the routes after the group.
  private def check_lite_under(lines : Array(String), idx : Int32) : String?
    (idx - 1).downto(0) do |i|
      return check_handler_body(lines, i) if lines[i].matches?(/^\s*under\b/)
    end
    nil
  end

  # A Mojolicious full app's bridge: `my $auth = $r->under('/')->to('session#check')`
  # and then `$auth->get(...)`, possibly through more `->any(...)` children
  # or an `->under(...)` on the route line itself. Every route below a
  # bridge dispatches only when the bridge action returns true.
  private def check_mojo_bridge(lines : Array(String), idx : Int32) : String?
    return unless m = lines[idx].match(/\A\s*(\$\w+.*?)->(?:get|post|put|patch|delete|options|any|websocket)\s*\(/)
    chain = m[1]
    8.times do
      if description = mojo_under_guard(chain)
        return description
      end
      return unless parent = chain.match(/\A\$(\w+)/)
      return unless found = route_assignment(lines, parent[1], idx)
      chain, idx = found
    end
    nil
  end

  # The last `my $name = $parent->...;` statement above `before`, joined
  # across lines; nil when the right side is not a route chain.
  private def route_assignment(lines : Array(String), name : String, before : Int32) : {String, Int32}?
    head = /\A\s*(?:my\s+)?\$#{name}\s*(?:=(?![=~>])|$)/
    (before - 1).downto(0) do |i|
      next unless lines[i].matches?(head)
      statement = lines[i...[i + 5, lines.size].min].join(" ")
      statement = statement[0, statement.index(';') || statement.size]
      rhs = statement.partition('=')[2].strip
      return rhs.matches?(/\A\$\w+->/) ? {rhs, i} : nil
    end
    nil
  end

  private def mojo_under_guard(chain : String) : String?
    return unless at = chain.index("->under")
    bridge = chain[at..]
    m = bridge.match(/->to\s*\(\s*['"]([\w:-]+)#(\w+)['"]/) ||
        bridge.match(/controller\s*=>\s*['"]([\w:-]+)['"]\s*,\s*action\s*=>\s*['"](\w+)['"]/)
    return unless m
    "Mojolicious under #{m[1]}##{m[2]}" if mojo_bridge_action_guard?(m[1], m[2])
  end

  # The bridge action reads who the caller is and has a path that returns
  # false (`return 0`, `return undef`, `? 1 : $c->redirect...`). The
  # identity read may sit in a `$self->helper` of the same file, two hops deep.
  private def mojo_bridge_action_guard?(controller : String, action : String) : Bool
    @bridge_verdicts.fetch({controller, action}) do |key|
      suffix = "/#{mojo_camelize(controller).gsub("::", "/")}.pm"
      @bridge_verdicts[key] = collect_files_by_extension(".pm").select(&.ends_with?(suffix)).any? do |file|
        next false unless (lines = read_file_lines(file)) && (body = perl_sub_body(lines, action))
        body.matches?(/\breturn\s+(?:0|undef)\b|\breturn\s*;|\breturn\s+\$\w+->|\?\s*1\s*:/) && reaches_identity?(lines, body, action)
      end
    end
  end

  private def reaches_identity?(lines : Array(String), body : String, name : String) : Bool
    seen = Set{name}
    frontier = [body]
    3.times do
      return true if frontier.any?(&.matches?(PERL_IDENTITY))
      callees = frontier.flat_map { |text| text.scan(/\$(?:self|c)->(\w+)/).map(&.[1]) }
      frontier = callees.select { |callee| seen.add?(callee) }.compact_map { |callee| perl_sub_body(lines, callee) }
    end
    false
  end

  PERL_IDENTITY = /\b(?:current_user|is_user_authenticated|user_exists|logged_in_user)\b|->\s*session\s*(?:\(\s*['"]|->\s*\{\s*['"]?)\w*(?:user|login|account)|\bAuthorization\b|->\s*header\s*\(\s*['"][^'"]*(?:auth|token|key)/i

  # Mojolicious::Util::camelize: `api_key` -> `ApiKey`, `admin-user` ->
  # `Admin::User`; a name starting uppercase is used as is.
  private def mojo_camelize(name : String) : String
    return name if name[0]?.try(&.uppercase?)
    name.split('-').map(&.split('_').map(&.capitalize).join).join("::")
  end

  private def perl_sub_body(lines : Array(String), name : String) : String?
    return unless start = lines.index(&.matches?(/\A\s*sub\s+#{Regex.escape(name)}\b/))
    depth = 0
    String.build do |io|
      lines[start, 80].each do |line|
        io << line << '\n'
        depth += line.count('{') - line.count('}')
        break if depth <= 0 && line.includes?('}')
      end
    end
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
