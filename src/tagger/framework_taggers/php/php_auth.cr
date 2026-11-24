require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/php_block_parser"
require "./laravel_access"
require "./php_access"

@[Noir::TaggerFor(key: "php_auth", name: "PHP Auth Tagger", desc: "Identifies PHP authentication patterns (Laravel, Symfony, CakePHP)", order: 140)]
class PhpAuthTagger < FrameworkTagger
  # Laravel middleware patterns.
  #
  # `(?:->|::)` so the leading form is recognized too: `Route::middleware('auth')
  # ->get('/x', …)` is as common as the chained `->middleware('auth')`, and
  # only the chained one used to match. That gap was invisible while the
  # ±3-line window happened to reach the *previous* route's `->middleware(…)`
  # — a route tagged correctly by accident is still a tagger that cannot read
  # the form in front of it.
  LARAVEL_ROUTE_MIDDLEWARE = [
    {/(?:->|::)middleware\s*\(\s*['"]auth['"]/, "Laravel auth middleware"},
    {/(?:->|::)middleware\s*\(\s*['"]auth:api['"]/, "Laravel auth:api middleware"},
    {/(?:->|::)middleware\s*\(\s*['"]auth:sanctum['"]/, "Laravel Sanctum auth"},
    {/(?:->|::)middleware\s*\(\s*['"]auth:web['"]/, "Laravel web auth"},
    {/(?:->|::)middleware\s*\(\s*['"]verified['"]/, "Laravel verified middleware"},
    # `[^\]]*`, not `.*`: stay inside the middleware list, or
    # `middleware(['guest'])->prefix('auth')` reads the prefix as the guard.
    {/(?:->|::)middleware\s*\(\s*\[[^\]]*['"]auth['"]/, "Laravel auth middleware"},
    # Jetstream's `Route::middleware(['auth:sanctum', ..., 'verified'])`
    {/(?:->|::)middleware\s*\(\s*\[[^\]]*['"]auth:[\w,]+['"]/, "Laravel auth middleware"},
  ]

  # `Route::middleware('auth')->group(function () { ... })` and the older
  # `Route::group(['middleware' => 'auth'], function () { ... })`: every route
  # declared inside the closure inherits the middleware. Breeze's
  # routes/web.php and routes/auth.php are built this way. The middleware value
  # is one string or one bracketed list; the match must not run past it into
  # later keys (`'middleware' => 'guest', 'prefix' => 'auth'`).
  LARAVEL_GROUP_OPEN       = /(?:->|::)group\s*\(\s*(?:\[(?:[^\[\]]|\[[^\]]*\])*\]\s*,\s*)?(?:static\s+)?(?:function|fn)\b/
  LARAVEL_GROUP_MIDDLEWARE = /['"]middleware['"]\s*=>\s*(?:\[[^\]]*?)?['"](?:auth(?::[\w,]+)?|verified)['"]/

  # `Route::get(...)->withoutMiddleware('auth')`: the route opts out of the
  # auth middleware its group applies.
  LARAVEL_WITHOUT_AUTH = [{/->withoutMiddleware\s*\(\s*(?:\[[^\]]*)?['"]auth(?::[\w,]+)?['"]/, ""}]

  # Laravel controller middleware
  LARAVEL_CONTROLLER_MIDDLEWARE = [
    {/\$this->middleware\s*\(\s*['"]auth['"]/, "Laravel controller auth middleware"},
    {/\$this->middleware\s*\(\s*['"]auth:/, "Laravel controller auth middleware"},
    {/\$this->authorizeResource\s*\(/, "Laravel authorizeResource"},
  ]

  # Laravel Gate/Policy checks in action body
  LARAVEL_AUTH_CHECKS = [
    {/Gate::allows\s*\(/, "Laravel Gate authorization"},
    {/Gate::authorize\s*\(/, "Laravel Gate authorization"},
    {/\$this->authorize\s*\(/, "Laravel Policy authorization"},
    {/auth\(\)->check\(\)/, "Laravel auth check"},
    {/Auth::check\(\)/, "Laravel Auth::check"},
    {/\$request->user\(\)/, "Laravel request user check"},
  ]

  # `IsGranted('PUBLIC_ACCESS')` (and the pre-5.1 `IS_AUTHENTICATED_ANONYMOUSLY`)
  # grants every caller, so it is not a guard.
  SYMFONY_NOT_PUBLIC = /(?!\s*(?:attribute\s*:\s*)?(?:['"]|\\?[\w\\]+::)(?:PUBLIC_ACCESS|IS_AUTHENTICATED_ANONYMOUSLY)\b)/.source

  # Symfony security attributes/annotations
  SYMFONY_PATTERNS = [
    {/#\[IsGranted\s*\(#{SYMFONY_NOT_PUBLIC}/, "Symfony #[IsGranted]"},
    # A quoted expression first: NelmioApiDoc's `@Security(name="Bearer")`
    # only documents an auth scheme.
    {/#\[Security\s*\(\s*(?:expression\s*:\s*)?['"]/, "Symfony #[Security]"},
    {/@Security\s*\(\s*['"]/, "Symfony @Security annotation"},
    {/@IsGranted\s*\(#{SYMFONY_NOT_PUBLIC}/, "Symfony @IsGranted annotation"},
    {/\$this->denyAccessUnlessGranted\s*\(/, "Symfony denyAccessUnlessGranted"},
    {/\$this->isGranted\s*\(/, "Symfony isGranted check"},
  ]

  # CakePHP auth patterns
  CAKEPHP_PATTERNS = [
    {/\$this->Authentication->/, "CakePHP Authentication component"},
    {/\$this->Authorization->authorize/, "CakePHP Authorization"},
    {/\$this->loadComponent\s*\(\s*['"]Authentication['"]/, "CakePHP Authentication component"},
  ]

  # Generic PHP auth patterns
  GENERIC_PATTERNS = [
    # The previous `session_start().*$_SESSION['user` required both tokens
    # on one physical line; under the per-line body scan that essentially
    # never matched. Key on a guarded `$_SESSION['user...]` access instead
    # (isset/!isset/empty), which is the actual auth signal and excludes a
    # bare `session_start();` bootstrap used on public pages too.
    {/(?:isset|empty|!\s*isset)\s*\(\s*\$_SESSION\s*\[\s*['"]user/, "PHP session user guard"},
    {/\$_SERVER\[['"]PHP_AUTH_USER['"]/, "PHP HTTP Basic Auth"},
  ]

  # Slim / Yii / CodeIgniter additional patterns
  SLIM_YII_CI_PATTERNS = [
    # Slim
    {/\->add\s*\(\s*['"]?auth/i, "Slim auth middleware"},
    {/\bAuthorization\b.*header/i, "Slim Authorization header check"},
    # Yii
    {/\bAccessControl\b/, "Yii AccessControl filter"},
    {/\bAuthMethod\b/, "Yii AuthMethod"},
    {/\bHttpBearerAuth\b/, "Yii HttpBearerAuth"},
    {/\bCompositeAuth\b/, "Yii CompositeAuth"},
    {/\bbeforeAction\b.*auth/i, "Yii beforeAction auth"},
    # CodeIgniter (4+ filters, controller before)
    {/->before\s*\(\s*['"]?auth/i, "CodeIgniter before auth filter"},
    {/\$this->beforeFilter/i, "CodeIgniter beforeFilter"},
    {/\bauthFilter\b/i, "CodeIgniter authFilter"},
  ]

  # A line that starts a *different* route or method than the one being
  # inspected: `Route::get('/x', …)`, `$app->post('/x', …)`, `Route::resource`,
  # a named `function foo(` declaration. Anonymous closures (`function () {`)
  # are deliberately excluded — those are part of the current route statement.
  #
  # Every window this tagger scans is bounded by it. A fixed ±N-line window is
  # not a statement: two one-line routes stacked on top of each other put the
  # second's `->middleware('auth')` inside the first's window, and the public
  # route came back tagged as protected.
  #
  # The `$app->get(…)` form requires a path literal starting with `/` so that
  # an ordinary body call — `$request->get('id')` — is not mistaken for the
  # start of the next route and does not cut a scan short.
  STATEMENT_BOUNDARY = /(?:Route|Router)::(?:get|post|put|patch|delete|options|head|any|query|match|addRoute|resource|apiResource)\s*\(|\$\w+\s*->\s*(?:get|post|put|patch|delete|options|head|any|query|map|group)\s*\(\s*['"]\/|\bfunction\s+\w+\s*\(/i

  def self.target_techs : Array(String)
    [
      "php_laravel", "php_symfony", "php_cakephp", "php_pure",
      "php_slim", "php_yii", "php_codeigniter",
    ]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @group_auth = Hash(String, Array(Guard?)).new
  end

  # A guard's description and, on a Laravel route, what it requires.
  alias Guard = Tuple(String, Array(Access::Clause))

  # Per line of a routes file, the auth middleware of the innermost
  # `->group(function () {` closure enclosing it, tracked by brace depth.
  private def group_auth_lines(path : String, lines : Array(String)) : Array(Guard?)
    @group_auth[path] ||= begin
      covered = Array(Guard?).new(lines.size, nil)
      frames = [] of {Int32, Guard?}
      depth = 0
      statement = ""
      lines.each_with_index do |line, idx|
        code = line.gsub(/'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"/) { |str| str.gsub(/[{}]/, "") }.sub(%r{^\s*(?://|#|\*).*}, "")
        statement = "#{statement} #{code}"
        covered[idx] = frames.reverse_each.compact_map(&.[1]).first?
        if code.matches?(LARAVEL_GROUP_OPEN)
          guard = LARAVEL_ROUTE_MIDDLEWARE.find { |pattern, _| statement.matches?(pattern) }.try { |(_, desc)| {desc, laravel_requires(desc, statement)} }
          if guard.nil? && statement.matches?(LARAVEL_GROUP_MIDDLEWARE)
            value = statement.match(GROUP_MIDDLEWARE_KEY).try { |key| LaravelAccess.value_at(statement, key.end(0)) }
            guard = {"Laravel auth middleware", listed_requires(value.try { |text| LaravelAccess.elements(text) }, statement.strip)}
          end
          frames << {depth, guard}
        end
        depth += code.count('{') - code.count('}')
        while (top = frames.last?) && depth <= top[0]
          frames.pop
        end
        stripped = code.strip
        statement = "" if stripped.ends_with?(';') || stripped.ends_with?('{') || stripped.ends_with?('}')
      end
      covered
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

      if endpoint.details.technology == "php_cakephp" && (cake = cakephp_guard(path_info.path, lines, line_idx))
        description, unread = cake
        # AuthenticationComponent::doIdentityCheck refuses a request without an identity.
        requires = [Access::Clause.new([Access::Atom.new(:authenticated)], description)]
        requires << Access::Clause.unresolved(unread, description) if unread
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "php_auth", requires: requires))
        return
      end
      if endpoint.details.technology == "php_yii" && (guard = yii_guard(path_info.path, lines, line_idx))
        endpoint.add_tag(Tag.new("auth", "Protected by #{guard[0]}", "php_auth", requires: guard[1]))
        return
      end

      # A route that calls `->withoutMiddleware('auth')` is outside the auth
      # middleware its group (or the group-opening line above it) applies.
      unless check_patterns_near_line(lines, line_idx, LARAVEL_WITHOUT_AUTH, 10)
        # Check route-level middleware (Laravel + Slim groups etc.)
        route_patterns = LARAVEL_ROUTE_MIDDLEWARE + SLIM_YII_CI_PATTERNS
        if found = check_patterns_near_line(lines, line_idx, route_patterns, 3)
          return add_guard(endpoint, found[0], found[1])
        end

        if guard = group_auth_lines(path_info.path, lines)[line_idx]
          return add_guard(endpoint, "#{guard[0]} (group)", guard[1])
        end
      end

      # Check controller constructor middleware (walk back to find class),
      # Symfony attributes/annotations above the method, then the method body.
      if found = check_controller_middleware(lines, line_idx) || check_annotations_above(lines, line_idx) || check_method_body(lines, line_idx)
        return add_guard(endpoint, found[0], found[1])
      end
    end
  end

  SYMFONY_ATTRIBUTE_GUARDS = Set{"Symfony #[IsGranted]", "Symfony #[Security]", "Symfony @Security annotation", "Symfony @IsGranted annotation"}

  private def add_guard(endpoint : Endpoint, description : String, line : String) : Nil
    # The Symfony analyzer read every security attribute of this action and
    # its class into its own tag under this tagger name: the one line read
    # here would only add an unknown to it.
    return if SYMFONY_ATTRIBUTE_GUARDS.includes?(description) && endpoint.tags.any? { |tag| symfony_action_tag?(tag) }
    add_guard(endpoint, description, laravel_requires(description, line))
  end

  private def symfony_action_tag?(tag : Tag) : Bool
    tag.name == "auth" && tag.tagger == "php_auth" && !tag.requires.nil? &&
      tag.description.starts_with?("Protected by Symfony ") && !tag.description.starts_with?("Protected by Symfony access_control")
  end

  # Only a Laravel route says what it requires: its analyzer tags it under
  # this tagger name with `requires` set, and a tag without it merged into
  # that one would lose its unknown.
  #
  # When the analyzer already tagged the route, it read the same statement
  # with the app's alias table (which this tagger has not got), so only what
  # this tagger read itself is added: its unread clauses would only hide
  # what the analyzer read (`role:admin` under a Spatie alias).
  private def add_guard(endpoint : Endpoint, description : String, requires : Array(Access::Clause)) : Nil
    laravel = endpoint.details.contributing_technologies.includes?("php_laravel")
    if laravel && endpoint.tags.any? { |tag| tag.name == "auth" && tag.tagger == "php_auth" && tag.requires }
      requires = requires.reject(&.any_of.all?(&.kind.unresolved?))
    end
    endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "php_auth", requires: (requires if laravel)))
  end

  LARAVEL_AUTH_GUARDS = Set{
    "Laravel auth middleware", "Laravel auth:api middleware", "Laravel Sanctum auth",
    "Laravel web auth", "Laravel controller auth middleware",
  }
  MIDDLEWARE_CALL      = /middleware\s*\(/
  GROUP_MIDDLEWARE_KEY = /['"]middleware['"]\s*=>\s*/
  GATE_CALL_START      = /\$this\s*->\s*authorize\s*\(|Gate::authorize\s*\(/

  # What the guard `description` found on `line` requires: the whole
  # middleware list it matched in, or the gate call. A check that does not
  # itself turn a guest away (`Gate::allows`, `$request->user()`) or a pattern
  # of another framework keeps the conservative reading of an `auth` tag.
  private def laravel_requires(description : String, line : String) : Array(Access::Clause)
    if description == "Laravel verified middleware" || LARAVEL_AUTH_GUARDS.includes?(description)
      elements = line.index(MIDDLEWARE_CALL).try do |at|
        LaravelAccess.arguments(line, line.index!('(', at)).try &.flat_map { |arg| LaravelAccess.elements(arg) }
      end
      listed_requires(elements, line.strip)
    elsif start = line.index(GATE_CALL_START)
      call = line[start..].strip.rchop(';').strip
      LaravelAccess.floor(Access.clauses(LaravelAccess.gate_call(call), call), call)
    else
      unread(line.strip)
    end
  end

  # Each entry of a middleware list, read without the app's alias table;
  # nil (a list that does not close on the line) is unread. `verified` is
  # the one non-auth name this tagger reports as a guard.
  private def listed_requires(elements : Array(String)?, source : String) : Array(Access::Clause)
    return unread(source) unless elements
    clauses = elements.flat_map do |element|
      entry = LaravelAccess.entry(element) { |name| name }
      next [Access::Clause.unresolved(element, element)] unless entry
      if cnf = LaravelAccess.middleware(entry)
        next Access.clauses(cnf, entry)
      end
      next [] of Access::Clause if entry != "verified" && LaravelAccess.non_access?(entry)
      [Access::Clause.unresolved(entry, entry)]
    end
    clauses.empty? ? unread(source) : LaravelAccess.floor(clauses.uniq!(&.any_of), source)
  end

  # How `Access.of` reads an `auth` tag without `requires`.
  private def unread(source : String) : Array(Access::Clause)
    [Access::Clause.new([Access::Atom.new(:authenticated)], source), Access::Clause.unresolved(source, source)]
  end

  # CakePHP's AuthenticationComponent requires an identity on every action of
  # a controller that loads it (directly or through a base class such as
  # `AppController`), except the actions passed to `allowUnauthenticated` /
  # `addUnauthenticatedActions`. CakePHP routes name their target in an
  # options array (`['prefix' => 'Admin', 'controller' => 'Users', 'action'
  # => 'view']`) or a `'Admin/Users::view'` string.
  CAKE_AUTHN_COMPONENT = /->\s*loadComponent\s*\(\s*['"](?:Authentication\.)?Authentication['"]/
  # An exempt list that is not a literal array cannot be read: the
  # controller is then left untagged.
  CAKE_UNAUTHENTICATED = /->\s*(?:allowUnauthenticated|addUnauthenticatedActions)\s*\(\s*(\[[^\]]*\])?/
  # `loadComponent(..., ['requireIdentity' => false])` or
  # `setConfig('requireIdentity', false)`: no action requires an identity.
  CAKE_NO_IDENTITY     = /['"]requireIdentity['"]\s*(?:=>|,)\s*false\b/
  CAKE_AUTHZ_COMPONENT = /->\s*loadComponent\s*\(\s*['"](?:Authorization\.)?Authorization['"]/
  CAKE_TARGET_STRING   = /['"](?:\w+(?:\/\w+)*\.)?((?:\w+\/)*)(\w+)::(\w+)['"]/
  CAKE_EXTENDS         = /\bclass\s+\w+\s+extends\s+\\?(?:\w+\\)*(\w+)/
  CAKE_PREFIX_SCOPE    = /->\s*prefix\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:\[[^\]]*\]\s*,\s*)?(?:static\s+)?\z/

  # ponytail: the unauthenticated lists of the whole class chain are unioned,
  # though `allowUnauthenticated` replaces the list; a base class can only
  # widen what is exempt, never narrow it.
  # Besides the description, the authorization layer it could not read: the
  # Authorization component or middleware (its policy checks), or a base
  # controller outside the scan.
  private def cakephp_guard(path : String, lines : Array(String), line_idx : Int32) : {String, String?}?
    statement = lines[line_idx..statement_end(lines, line_idx, 5)].join(' ')
    if target = statement.match(CAKE_TARGET_STRING)
      prefix, controller, action = target[1].rchop('/'), target[2], target[3]
    else
      controller = statement.match(/['"]controller['"]\s*=>\s*['"]([\w\/]+)['"]/).try(&.[1]) || return
      action = statement.match(/['"]action['"]\s*=>\s*['"](\w+)['"]/).try(&.[1])
      prefix = statement.match(/['"]prefix['"]\s*=>\s*['"]([\w\/]+)['"]/).try(&.[1])
    end
    prefix = cakephp_scope_prefix(path, lines, line_idx) if prefix.nil? || prefix.empty?
    # `config/routes.php` of the app or of a plugin: its `src/Controller`.
    root = File.dirname(File.dirname(path))
    file = File.join([root, "src", "Controller", prefix, "#{controller}Controller.php"].reject(&.empty?))
    exempt = Set(String).new
    loaded = false
    unread = read_file(File.join(root, "src", "Application.php")).try { |app| "AuthorizationMiddleware" if app.includes?("AuthorizationMiddleware") }
    5.times do
      raw = read_file(file) || break
      # Comments dropped: a commented-out `loadComponent` loads nothing.
      content = Noir::PhpLexer.new(raw).without_comments(keep_docblocks: false)
      return if content.matches?(CAKE_NO_IDENTITY)
      loaded ||= content.matches?(CAKE_AUTHN_COMPONENT)
      content.scan(CAKE_UNAUTHENTICATED) do |call|
        list = call[1]? || return
        list.scan(/['"](\w+)['"]/) { |name| exempt << name[1] }
      end
      unread ||= "Authorization component" if content.matches?(CAKE_AUTHZ_COMPONENT)
      parent = content.match(CAKE_EXTENDS).try(&.[1]) || break
      next_file = cakephp_class_file(file, root, parent)
      unread ||= "#{parent} (not in the scan)" unless next_file || parent == "Controller"
      file = next_file || break
    end
    return unless loaded
    return if action ? exempt.includes?(action) : !exempt.empty?
    {"CakePHP AuthenticationComponent (identity required)", unread}
  end

  # The controller namespace of the `$routes->prefix('Admin', function ...)`
  # scopes enclosing the route, outermost first (`admin` reads as `Admin`).
  private def cakephp_scope_prefix(path : String, lines : Array(String), line_idx : Int32) : String
    content = read_file(path) || return ""
    parser = @php_parsers[path] ||= Noir::PhpBlockParser.new(content)
    offset = lines[0, line_idx].sum { |line| line.size + 1 }
    names = parser.path(offset).select(&.kind.closure?).compact_map do |closure|
      content[[closure.start - 200, 0].max...closure.start].match(CAKE_PREFIX_SCOPE).try(&.[1])
    end
    names.join('/', &.lchop('/').split('/').join('/', &.split(/[_-]/).join(&.capitalize)))
  end

  # The base class's file: beside the controller, else the nearest
  # `src/Controller/<Name>.php` up from it (a plugin's controllers extend the
  # app's `AppController`). Never the file it is asked from.
  private def cakephp_class_file(from : String, root : String, name : String) : String?
    sibling = File.join(File.dirname(from), "#{name}.php")
    return sibling if sibling != from && read_file(sibling)
    dir = root
    4.times do
      candidate = File.join(dir, "src", "Controller", "#{name}.php")
      return candidate if candidate != from && read_file(candidate)
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    nil
  end

  # Yii's AccessControl filter, declared in the controller's `behaviors()`:
  # it covers the actions its `only` / `except` select, and a guest gets
  # what the first rule matching a guest says (a rule with no `roles`, or
  # with `'?'`); no matching rule denies. `'@'` and named roles never match
  # a guest.
  YII_ACCESS_CONTROL = /\bAccessControl::(?:class\b|className\s*\()/
  YII_RULE_UNKNOWN   = Set{"verbs", "ips", "matchCallback", "controllers", "permissions"}

  @php_parsers = Hash(String, Noir::PhpBlockParser).new

  private def yii_guard(path : String, lines : Array(String), line_idx : Int32) : {String, Array(Access::Clause)}?
    name = lines[line_idx].match(/\bfunction\s+action([A-Z]\w*)\s*\(/).try(&.[1]) || return
    action = name.gsub(/(?<=[a-z0-9])[A-Z]/) { |upper| "-#{upper}" }.downcase
    content = read_file(path) || return
    return unless content.includes?("AccessControl")
    parser = @php_parsers[path] ||= Noir::PhpBlockParser.new(content)
    lexer = parser.lexer
    content.scan(YII_ACCESS_CONTROL) do |match|
      pos = match.begin(0)
      next unless lexer.in_code?(pos)
      open = enclosing_bracket(lexer.masked, pos) || next
      filter = yii_entries(parser, open)
      next unless yii_selects?(lexer, filter, action)
      # Rules the scan cannot read (`$this->accessRules()`) decide nothing it can see.
      rules = if rules_range = filter["rules"]?
                parser.array_entries(array_open(lexer, rules_range) || return) || return
              else
                [] of Noir::PhpBlockParser::ArrayEntry
              end
      rules.each do |entry|
        rule = yii_entries(parser, array_open(lexer, entry.value) || return)
        actions = rule["actions"]?.try { |range| yii_strings(lexer, range) }
        next if actions && !actions.includes?(action)
        roles = rule["roles"]?.try { |range| yii_strings(lexer, range) }
        next if roles && !roles.empty? && !roles.includes?("?")
        return if rule.keys.any? { |key| YII_RULE_UNKNOWN.includes?(key) }
        allow = rule["allow"]?.try { |range| lexer.source(range).strip.downcase == "true" }
        return if allow
        break
      end
      description = "Yii AccessControl (no rule admits a guest)"
      return {description, yii_requires(parser, open, filter, rules, action, description)}
    end
    nil
  end

  YII_FILTER_KEYS = Set{"class", "only", "except", "rules", "denyCallback"}
  YII_RULE_KEYS   = Set{"allow", "actions", "roles", "denyCallback"}

  # Behaviors another class of the file, a parent's `behaviors()` or a
  # second AccessControl filter attach, which must allow too.
  YII_OTHER_FILTERS = /\bclass\s+\w+[^{;]*\{[\s\S]*\bclass\s+\w+[^{;]*\{|\bparent::behaviors\b|\bAccessControl::(?:class\b|className\s*\()[\s\S]*\bAccessControl::(?:class\b|className\s*\()/

  # What a signed-in caller needs under the filter's rules. A filter key
  # such as `ruleConfig` (another rule class) or `user`, an entry without a
  # key (`...$extra`), or another filter the reader does not combine leaves
  # them unread.
  private def yii_requires(parser : Noir::PhpBlockParser, open : Int32, filter : Hash(String, Range(Int32, Int32)),
                           rules : Array(Noir::PhpBlockParser::ArrayEntry), action : String, description : String) : Array(Access::Clause)
    lexer = parser.lexer
    code = lexer.without_comments(keep_docblocks: false)
    unread = filter.keys.find { |name| !YII_FILTER_KEYS.includes?(name) }.try { |key| "#{key} => #{lexer.source(filter[key])}" }
    unread ||= lexer.source(open..(lexer.matching_delimiter(open) || open)) if !yii_keyed?(parser, open) || code.matches?(YII_OTHER_FILTERS)
    if unread
      return Access.clauses([[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, unread.gsub(/\s+/, " "))]], description)
    end
    read = rules.map do |entry|
      source = lexer.source(entry.value).gsub(/\s+/, " ")
      open = array_open(lexer, entry.value)
      next PhpAccess::YiiRule.new(source, false, nil, nil, false) unless open
      rule = yii_entries(parser, open)
      actions = rule["actions"]?.try { |range| yii_literals(parser, range) }
      roles = rule["roles"]?.try { |range| yii_literals(parser, range) }
      allow = rule["allow"]?.try { |range| lexer.source(range).strip.downcase }
      readable = yii_keyed?(parser, open) && rule.keys.all? { |name| YII_RULE_KEYS.includes?(name) } && (allow.nil? || allow == "true" || allow == "false") &&
                 (!rule.has_key?("actions") || actions) && (!rule.has_key?("roles") || roles)
      PhpAccess::YiiRule.new(source, allow == "true", actions, roles, !!readable)
    end
    Access.clauses(PhpAccess.yii_signed_in(read, action), description)
  end

  private def yii_keyed?(parser : Noir::PhpBlockParser, open : Int32) : Bool
    parser.array_entries(open).try(&.all?(&.key)) || false
  end

  # The entries of the array literal spanning `range`, when every one is a
  # string literal.
  private def yii_literals(parser : Noir::PhpBlockParser, range : Range(Int32, Int32)) : Array(String)?
    entries = parser.array_entries(array_open(parser.lexer, range) || return) || return
    entries.map { |entry| (LaravelAccess.literal(parser.lexer.source(entry.value)) unless entry.key) || return }
  end

  # The `[` (or `array(`'s `(`) of the innermost array literal holding `pos`.
  private def enclosing_bracket(masked : Array(Char), pos : Int32) : Int32?
    depth = 0
    (pos - 1).downto(0) do |i|
      case masked[i]
      when ']', ')' then depth += 1
      when '['
        return i if depth == 0
        depth -= 1
      when '('
        return i if depth == 0 && masked[[i - 5, 0].max...i].join.rstrip.downcase.ends_with?("array")
        depth -= 1
      end
      return if depth < 0
    end
    nil
  end

  # Where the array literal spanning `range` opens: its `[`, or the `(` of
  # `array(`. Nil for anything else (a call, a variable).
  private def array_open(lexer : Noir::PhpLexer, range : Range(Int32, Int32)) : Int32?
    text = lexer.source(range)
    return range.begin if text.starts_with?('[')
    text.match(/\Aarray\s*\(/i).try { |m| range.begin + m.end(0) - 1 }
  end

  # An array literal's string-keyed entries, key => value range.
  private def yii_entries(parser : Noir::PhpBlockParser, open : Int32) : Hash(String, Range(Int32, Int32))
    entries = Hash(String, Range(Int32, Int32)).new
    parser.array_entries(open).try &.each do |entry|
      key = entry.key || next
      entries[parser.lexer.source(key).strip.strip("'\"")] = entry.value
    end
    entries
  end

  private def yii_strings(lexer : Noir::PhpLexer, range : Range(Int32, Int32)) : Array(String)
    lexer.source(range).scan(/['"]([^'"]*)['"]/).map(&.[1])
  end

  # `only` / `except` patterns, with the `*` wildcard Yii accepts since 2.0.9.
  private def yii_selects?(lexer : Noir::PhpLexer, filter : Hash(String, Range(Int32, Int32)), action : String) : Bool
    only = filter["only"]?.try { |range| yii_strings(lexer, range) }
    except = filter["except"]?.try { |range| yii_strings(lexer, range) } || [] of String
    hit = ->(patterns : Array(String)) { patterns.any? { |pattern| action.matches?(/\A#{Regex.escape(pattern).gsub("\\*", ".*")}\z/) } }
    (only.nil? || hit.call(only)) && !hit.call(except)
  end

  private def check_patterns_near_line(lines : Array(String), line_idx : Int32,
                                       patterns : Array(Tuple(Regex, String)),
                                       window : Int32) : Tuple(String, String)?
    (statement_start(lines, line_idx, window)..statement_end(lines, line_idx, window)).each do |idx|
      line = lines[idx]
      patterns.each do |pattern, desc|
        return {desc, line} if line.matches?(pattern)
      end
    end

    nil
  end

  # First line of the window: walk back at most `window` lines, stopping
  # *before* anything that belongs to the previous statement — another route
  # or method declaration, or a line that already terminated one (`});`,
  # `})->middleware('auth');`). Only an unterminated line above (`Route::
  # middleware('auth')->group(function () {`) is really part of this route.
  private def statement_start(lines : Array(String), line_idx : Int32, window : Int32) : Int32
    idx = line_idx - 1
    limit = [line_idx - window, 0].max

    while idx >= limit
      stripped = lines[idx].strip
      break if stripped.empty?
      break if stripped.matches?(STATEMENT_BOUNDARY)
      break if stripped.ends_with?(";") || stripped.ends_with?("}")
      idx -= 1
    end

    idx + 1
  end

  # Last line of the window: the route statement's own lines. Stops after the
  # line that closes it (balanced brackets, terminating `;`) and never reaches
  # the next route declaration.
  private def statement_end(lines : Array(String), line_idx : Int32, window : Int32) : Int32
    limit = [line_idx + window, lines.size - 1].min
    depth = bracket_depth(lines[line_idx])
    idx = line_idx

    while idx < limit
      stripped = lines[idx].strip
      break if depth <= 0 && (stripped.ends_with?(";") || stripped.ends_with?(","))
      nxt = lines[idx + 1].strip
      break if nxt.matches?(STATEMENT_BOUNDARY) || nxt.matches?(/\A(?:Route|Router)::/)
      idx += 1
      depth += bracket_depth(lines[idx])
    end

    idx
  end

  private def bracket_depth(line : String) : Int32
    (line.count('(') + line.count('{')) - (line.count(')') + line.count('}'))
  end

  private def check_controller_middleware(lines : Array(String), action_line : Int32) : Tuple(String, String)?
    # Walk backwards to find __construct or class-level middleware
    idx = action_line
    while idx >= 0
      current = lines[idx].strip

      LARAVEL_CONTROLLER_MIDDLEWARE.each do |pattern, desc|
        return {desc, current} if current.matches?(pattern)
      end

      break if current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  private def check_annotations_above(lines : Array(String), method_line : Int32) : Tuple(String, String)?
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      # The previous member ends here (`}`, `;`, a one-line `function x() {
      # ... }`): its attributes are not this route's.
      break if current.ends_with?('}') || current.ends_with?(';') || current.ends_with?('{') || current.matches?(/\bfunction\b/)

      all_patterns = SYMFONY_PATTERNS
      all_patterns.each do |pattern, desc|
        return {desc, current} if current.matches?(pattern)
      end

      idx -= 1
    end

    # `#[Route]` then `#[IsGranted]` is as protected as the reverse order.
    annotation_lines_below(lines, method_line, "#[").each do |below|
      SYMFONY_PATTERNS.each do |pattern, desc|
        return {desc, below} if below.matches?(pattern)
      end
    end

    nil
  end

  # Scan the handler's own body for auth calls.
  #
  # `brace_count` used to start at 0 on the line *after* the signature, so the
  # body's opening `{` was never counted and the count balanced back to 0 at
  # the closing `}` without the loop noticing — it only broke on `< 0`. The
  # walk then ran to its 15-line cap through the *next* method, and that
  # method's `$this->authorize(...)` was reported as this endpoint's guard.
  # Seed the depth from the signature line and stop as soon as the body it
  # opened closes again.
  private def check_method_body(lines : Array(String), method_line : Int32) : Tuple(String, String)?
    idx = method_line + 1
    end_idx = [method_line + 15, lines.size - 1].min
    signature = lines[method_line]
    brace_count = signature.count('{') - signature.count('}')
    entered = signature.includes?('{')

    while idx <= end_idx
      current = lines[idx]
      stripped = current.strip

      break if entered && brace_count <= 0
      break if stripped.matches?(STATEMENT_BOUNDARY)

      brace_count += current.count('{') - current.count('}')
      entered = true if current.includes?('{')
      break if brace_count < 0

      all_patterns = LARAVEL_AUTH_CHECKS + CAKEPHP_PATTERNS + GENERIC_PATTERNS + SLIM_YII_CI_PATTERNS
      all_patterns.each do |pattern, desc|
        return {desc, stripped} if stripped.matches?(pattern)
      end

      idx += 1
    end

    nil
  end
end
