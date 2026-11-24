require "../../../models/access"
require "../../../minilexers/php_lexer"
require "./laravel_access"

# Reads what the guards of PHP frameworks other than Laravel ask of the
# caller: Symfony security attributes, controller refusals and
# `access_control` roles, Drupal route requirements, WordPress permission
# callbacks, Nextcloud controller attributes and Yii access rules.
module PhpAccess
  extend self

  alias CNF = Access::CNF

  # -- Symfony ---------------------------------------------------------

  # AuthenticatedVoter's levels a signed-in caller passes. `_FULLY` also
  # turns away a remember-me login; no atom says how a caller signed in.
  SYMFONY_SIGNED_IN = Set{"IS_AUTHENTICATED", "IS_AUTHENTICATED_FULLY", "IS_AUTHENTICATED_REMEMBERED"}
  # Levels that need a signed-in caller and something more about the login.
  SYMFONY_SIGNED_IN_AND = Set{"IS_IMPERSONATOR", "IS_REMEMBERED"}
  SYMFONY_PUBLIC        = Set{"PUBLIC_ACCESS", "IS_AUTHENTICATED_ANONYMOUSLY"}

  # What `isGranted(attribute)` asks. RoleVoter votes only on `ROLE_`
  # attributes and AuthenticatedVoter on the `IS_*` levels; any other
  # attribute is up to an application voter, which may grant it to anyone,
  # so it is not read as something the caller holds.
  def symfony_attribute(attribute : String) : CNF
    if SYMFONY_PUBLIC.includes?(attribute)
      CNF.new
    elsif attribute.starts_with?("ROLE_")
      [[Access::Atom.new(:role, attribute)]]
    elsif SYMFONY_SIGNED_IN.includes?(attribute)
      [[Access::Atom.new(:authenticated)]]
    elsif SYMFONY_SIGNED_IN_AND.includes?(attribute)
      [[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, attribute)]]
    else
      [[Access::Atom.new(:unresolved, attribute)]]
    end
  end

  # The attributes the analyzer's description says surely refuse an
  # anonymous caller; any other is up to a voter.
  SYMFONY_CERTAIN = /\A(?:ROLE_\w+|IS_AUTHENTICATED(?:_\w+)?|IS_IMPERSONATOR|IS_REMEMBERED)\z/

  # A check that was not read exactly. Unless it is a voter's, it still
  # refuses anonymous callers.
  def symfony_unread(text : String, voter : Bool = false) : CNF
    unread = [[Access::Atom.new(:unresolved, text)]]
    voter ? unread : [[Access::Atom.new(:authenticated)]] + unread
  end

  # `#[IsGranted(...)]`, `@IsGranted(...)` or a later entry of an attribute
  # group, and `Security` given its expression string first: NelmioApiDoc's
  # `#[Security(name: 'Bearer')]` only documents a scheme.
  SYMFONY_ATTRIBUTE   = /(?:#\[|@|,\s*)(IsGranted|Security)\s*\(/
  SYMFONY_EXPRESSION  = /\A\s*(?:expression\s*:\s*)?['"]/
  AUTHENTICATED_VOTER = /\A\\?(?:[\w\\]*\\)?AuthenticatedVoter::(\w+)\z/
  CLASS_CONSTANT      = /\A\\?[\w\\]+::(\w+)\z/
  NAMED_ARGUMENT      = /\A\s*\w+\s*(?::(?!:)|=(?![=>]))/

  # Every security attribute in `text` (an action's or a class's
  # attributes and docblock). Symfony checks each one, those of the class
  # and of the method alike (`ControllerEvent::getAttributes` merges both;
  # SensioFrameworkExtraBundle's `@IsGranted` / `@Security` allow arrays,
  # so its listener merges them too).
  def symfony_attributes(text : String) : Array(Access::Clause)
    clauses = [] of Access::Clause
    text.scan(SYMFONY_ATTRIBUTE) do |match|
      call = text[(match.end(0) - 1)..].gsub(/\n\s*\*/, "\n")
      args = LaravelAccess.arguments(call, 0)
      source = args ? squeeze("#{match[1]}(#{args.join(", ")})") : match[1]
      if match[1] == "Security"
        next unless call.lchop('(').matches?(SYMFONY_EXPRESSION)
        clauses.concat(Access.clauses(symfony_unread(source), source))
      else
        clauses.concat(Access.clauses(granted(args), source))
      end
    end
    clauses
  end

  private def granted(args : Array(String)?) : CNF
    return symfony_unread("IsGranted") unless args
    positional = args.first?.try { |arg| arg unless arg.matches?(NAMED_ARGUMENT) }
    expression = positional || args.find(&.matches?(/\A\s*attribute\s*:/)).try(&.sub(/\A\s*attribute\s*:/, ""))
    return symfony_unread("IsGranted(#{args.join(", ")})") unless expression
    expression = expression.strip
    if literal = LaravelAccess.literal(expression)
      symfony_attribute(literal)
    elsif voter = expression.match(AUTHENTICATED_VOTER)
      # Symfony's own constants hold their names.
      symfony_attribute(voter[1])
    else
      symfony_unread(expression, voter: !!expression.match(CLASS_CONSTANT).try { |constant| !constant[1].matches?(SYMFONY_CERTAIN) })
    end
  end

  DENY_CALL     = /(?:\$this\s*->\s*)?denyAccessUnlessGranted\s*\(/
  GRANTED_CALL  = /(?:\$this\s*->\s*)?\bisGranted\s*\(/
  LITERAL_FIRST = /\A\(\s*(['"])([^'"$\{]+)\1\s*[,)]/
  # `if (!$this->isGranted('X')) { throw ...`: the call is the whole condition.
  GRANTED_REFUSAL = /\A\s*\)\s*\{?\s*throw\b/
  EXITS           = /\b(?:return|throw|exit|die|goto|yield)\b/i

  # Each refusal an action's body (`own`) or a helper it calls makes:
  # `denyAccessUnlessGranted(...)`, and `isGranted(...)` when the body
  # throws an access-denied exception. Only a call that runs on every
  # request to the action reads exactly: a statement of its own at the top
  # of the body with no exit before it. An `isGranted` reads exactly only
  # as the whole negated condition of an `if` that throws.
  def symfony_refusals(body : String, own : Bool) : Array(Access::Clause)
    clauses = [] of Access::Clause
    return clauses unless body.includes?("Granted")
    lexer = Noir::PhpLexer.new(body, php_mode: true)
    masked = lexer.masked
    calls = [] of {Regex::MatchData, Bool}
    body.scan(DENY_CALL) { |match| calls << {match, true} }
    body.scan(GRANTED_CALL) { |match| calls << {match, false} } if body.includes?("AccessDenied")
    calls.each do |match, deny|
      next unless lexer.in_code?(match.begin(0))
      open = match.end(0) - 1
      close = lexer.matching_delimiter(open) || next
      source = squeeze(body[match.begin(0)..close])
      attribute = body[open..close].match(LITERAL_FIRST).try(&.[2])
      cnf = if attribute.nil?
              [[Access::Atom.new(:unresolved, source)]]
            elsif SYMFONY_PUBLIC.includes?(attribute)
              next
            else
              exact = own && (deny ? statement_start?(masked, match.begin(0)) : negated_condition?(masked, body, match.begin(0), close))
              exact ? symfony_attribute(attribute) : symfony_unread(source, voter: !attribute.matches?(SYMFONY_CERTAIN))
            end
      clauses.concat(Access.clauses(cnf, source))
    end
    clauses
  end

  # `pos` starts a statement at the top level of the body, and nothing
  # before it can leave the body.
  private def statement_start?(masked : Array(Char), pos : Int32) : Bool
    before = masked[0...pos].join
    return false if before.matches?(EXITS)
    return false unless before.count("{([") == before.count("})]")
    before[((before.rindex(/[;{}]/) || -1) + 1)..].strip.empty?
  end

  private def negated_condition?(masked : Array(Char), body : String, pos : Int32, close : Int32) : Bool
    head = masked[0...pos].join
    return false unless if_at = head.rindex(/\bif\s*\(\s*!\s*\z/)
    statement_start?(masked, if_at) && masked[(close + 1)..].join.matches?(GRANTED_REFUSAL)
  end

  # An `access_control` rule's `roles` (entries `allow_if: <expression>`
  # stand for its `allow_if`). Under the default affirmative strategy one
  # granting voter admits, so the entries are alternatives. Symfony 4.4's
  # unanimous strategy asked each voter about each attribute alone, making
  # them all required (5.4 and later ask about the list), so under another
  # strategy a list is not read.
  def symfony_roles(roles : Array(String), affirmative : Bool, note : String) : CNF
    voter = roles.any? { |role| role.starts_with?("allow_if:") ? role.ends_with?(note) : !role.matches?(SYMFONY_CERTAIN) }
    return symfony_unread(roles.join(", "), voter: voter) if roles.size > 1 && !affirmative
    readings = roles.map do |role|
      role.starts_with?("allow_if:") ? symfony_allow_if(role.lchop("allow_if:").rchop(note).strip) : symfony_attribute(role)
    end
    readings.reduce { |joined, reading| Access.either(joined, reading) }
  end

  ALLOW_IF_CHECK = /is_(?:fully_)?authenticated\(\s*\)|is_granted\(\s*(?:'([^']*)'|"([^"]*)")\s*\)/

  # An `allow_if` the security config reader kept as a guard: nothing but
  # `is_authenticated()`, `is_fully_authenticated()` and `is_granted('X')`
  # calls joined by `and`, each of which must hold.
  def symfony_allow_if(expression : String) : CNF
    cnf = CNF.new
    expression.scan(ALLOW_IF_CHECK) do |check|
      attribute = check[1]? || check[2]?
      cnf.concat(attribute ? symfony_attribute(attribute) : [[Access::Atom.new(:authenticated)]])
    end
    cnf.empty? ? symfony_unread(expression) : cnf
  end

  # -- Drupal ----------------------------------------------------------

  # A route requirement that checks the caller. PermissionAccessCheck splits
  # `_permission` on `,` (all required) before `+` (any one), without
  # trimming; RoleAccessCheck does the same for `_role`, trimming and
  # dropping empty ids. The `authenticated` role is every signed-in user;
  # `anonymous` admits only signed-out callers.
  def drupal_requirement(key : String, value : String) : CNF
    case key
    when "_permission"
      all = value.split(',')
      return all.map { |name| [drupal_atom(:permission, name, value)] } if all.size > 1
      [value.split('+').map { |name| drupal_atom(:permission, name, value) }]
    when "_role"
      all = value.split(',').map(&.strip).reject(&.empty?)
      return all.map { |name| [drupal_role(name)] } if all.size > 1
      any = value.split('+').map(&.strip).reject(&.empty?)
      any.empty? ? [[Access::Atom.new(:unresolved, "#{key}: #{value}")]] : [any.map { |name| drupal_role(name) }]
    else
      [[Access::Atom.new(:unresolved, "#{key}: #{value}")]]
    end
  end

  private def drupal_atom(kind : Access::Kind, name : String, value : String) : Access::Atom
    name.empty? ? Access::Atom.new(:unresolved, value) : Access::Atom.new(kind, name)
  end

  private def drupal_role(name : String) : Access::Atom
    case name
    when "authenticated" then Access::Atom.new(:authenticated)
    when "anonymous"     then Access::Atom.new(:unresolved, name)
    else                      Access::Atom.new(:role, name)
    end
  end

  # -- WordPress -------------------------------------------------------

  WP_CHECK   = /(?:current_user_can\s*\(\s*(?:'([\w-]+)'|"([\w-]+)")\s*\)|(is_user_logged_in)\s*\(\s*\))/.source
  WP_REFUSAL = /(?:false|new\s+\\?WP_Error\s*\((?:[^()]|\([^()]*\))*\))/.source
  # `return <check>;`, or WordPress core's `if ( ! <check> ) { return <error>; } return true;`.
  WP_RETURN    = Regex.new("\\A\\s*return\\s+#{WP_CHECK}\\s*;\\s*\\z")
  WP_IF_REFUSE = Regex.new("\\A\\s*if\\s*\\(\\s*!\\s*#{WP_CHECK}\\s*\\)\\s*(?:\\{\\s*return\\s+#{WP_REFUSAL}\\s*;\\s*\\}|return\\s+#{WP_REFUSAL}\\s*;)\\s*return\\s+true\\s*;\\s*\\z")
  WP_CLOSURE   = /\A(?:static\s+)?function\s*&?\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*\??[\w\\]+\s*)?\{(.*)\}\s*\z/m
  WP_ARROW     = /\A(?:static\s+)?fn\s*&?\s*\([^)]*\)\s*(?::\s*\??[\w\\]+\s*)?=>\s*(.*)\z/m

  # What a REST route's `permission_callback` (a closure's text, or the body
  # of the function it names) asks, when it is nothing but one capability
  # (`current_user_can('x')` with no object) or login check deciding the
  # result. Nil for anything else.
  def wordpress_permission(code : String) : CNF?
    code = Noir::PhpLexer.new(code, php_mode: true).without_comments(keep_docblocks: false).strip
    if found = code.match(WP_CLOSURE)
      code = found[1]
    elsif found = code.match(WP_ARROW)
      code = "return #{found[1].strip.rchop(';')};"
    end
    check = code.match(WP_RETURN) || code.match(WP_IF_REFUSE) || return
    if capability = check[1]? || check[2]?
      [[Access::Atom.new(:permission, capability)]]
    else
      [[Access::Atom.new(:authenticated)]]
    end
  end

  # -- Nextcloud -------------------------------------------------------

  # What Nextcloud's SecurityMiddleware asks of an action that is not a
  # `PublicPage`, from its attributes or docblock annotations: a login, then
  # an admin unless `NoAdminRequired`, a sub-admin under `SubAdminRequired`,
  # or an admin or delegated user under `AuthorizedAdminSetting`.
  # `ExAppRequired` replaces the login with an AppAPI session and
  # `AppApiAdminAccessWithoutUser` admits such a session too.
  # PasswordConfirmationMiddleware adds a recent password confirmation.
  def nextcloud(prelude : String) : CNF
    has = ->(name : String) { prelude.matches?(/\b#{name}\b/) }
    cnf = if has.call("ExAppRequired")
            [[Access::Atom.new(:unresolved, "ExAppRequired")]]
          else
            security = [[Access::Atom.new(:authenticated)]]
            if has.call("AuthorizedAdminSetting")
              security << [Access::Atom.new(:unresolved, "AuthorizedAdminSetting")]
            elsif has.call("SubAdminRequired")
              security << [Access::Atom.new(:unresolved, "SubAdminRequired")]
            elsif !has.call("NoAdminRequired")
              security << [Access::Atom.new(:unresolved, "admin (Nextcloud default)")]
            end
            if has.call("AppApiAdminAccessWithoutUser")
              security = Access.either(security, [[Access::Atom.new(:unresolved, "AppApiAdminAccessWithoutUser")]])
            end
            security
          end
    cnf << [Access::Atom.new(:unresolved, "PasswordConfirmationRequired")] if has.call("PasswordConfirmationRequired")
    cnf
  end

  # -- Yii -------------------------------------------------------------

  # One rule of Yii's AccessControl as read: `actions` / `roles` nil when
  # the key is absent; `readable` false when a key, an entry or `allow` was
  # not a literal the reader settles.
  record YiiRule, source : String, allow : Bool, actions : Array(String)?, roles : Array(String)?, readable : Bool

  # What a signed-in caller of `action` needs. AccessControl lets the first
  # rule matching the request decide and denies when none does; `'@'` is any
  # signed-in user, `'?'` a guest, and any other name an RBAC item passed to
  # `User::can()`, read as a role. A rule denying named roles leaves what
  # the later rules allow unread.
  def yii_signed_in(rules : Array(YiiRule), action : String) : CNF
    alternatives = [] of Access::Atom
    rules.each do |rule|
      next if (actions = rule.actions) && !actions.includes?(action)
      unless rule.readable
        alternatives << Access::Atom.new(:unresolved, rule.source)
        break
      end
      roles = rule.roles
      everyone = roles.nil? || roles.empty? || roles.includes?("@")
      named = (roles || [] of String).reject { |role| role == "?" || role == "@" }
      if everyone
        alternatives << Access::Atom.new(:authenticated) if rule.allow
        break
      end
      next if named.empty?
      unless rule.allow
        alternatives << Access::Atom.new(:unresolved, rule.source)
        break
      end
      alternatives.concat(named.map { |role| Access::Atom.new(:role, role) })
    end
    return [[Access::Atom.new(:deny)]] if alternatives.empty?
    # The guest verdict that tagged the action already refuses anonymous callers.
    return [[Access::Atom.new(:authenticated)], alternatives] if alternatives.any?(&.kind.unresolved?)
    [alternatives]
  end

  private def squeeze(text : String) : String
    text.gsub(/\s+/, " ").strip
  end
end
