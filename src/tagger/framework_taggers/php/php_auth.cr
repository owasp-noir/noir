require "../../../models/framework_tagger"
require "../../../models/endpoint"

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
    {/(?:->|::)middleware\s*\(\s*\[.*['"]auth['"]/, "Laravel auth middleware"},
  ]

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

  # Symfony security attributes/annotations
  SYMFONY_PATTERNS = [
    {/#\[IsGranted\s*\(/, "Symfony #[IsGranted]"},
    {/#\[Security\s*\(/, "Symfony #[Security]"},
    {/@Security\s*\(/, "Symfony @Security annotation"},
    {/@IsGranted\s*\(/, "Symfony @IsGranted annotation"},
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

      # Check route-level middleware (Laravel + Slim groups etc.)
      route_patterns = LARAVEL_ROUTE_MIDDLEWARE + SLIM_YII_CI_PATTERNS
      description = check_patterns_near_line(lines, line_idx, route_patterns, 3)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "php_auth"))
        return
      end

      # Check controller constructor middleware (walk back to find class)
      description = check_controller_middleware(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "php_auth"))
        return
      end

      # Check Symfony attributes/annotations above the method
      description = check_annotations_above(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "php_auth"))
        return
      end

      # Check method body for auth calls
      description = check_method_body(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "php_auth"))
        return
      end
    end
  end

  private def check_patterns_near_line(lines : Array(String), line_idx : Int32,
                                       patterns : Array(Tuple(Regex, String)),
                                       window : Int32) : String?
    (statement_start(lines, line_idx, window)..statement_end(lines, line_idx, window)).each do |idx|
      line = lines[idx]
      patterns.each do |pattern, desc|
        return desc if line.matches?(pattern)
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
      break if depth <= 0 && lines[idx].strip.ends_with?(";")
      nxt = lines[idx + 1].strip
      break if nxt.matches?(STATEMENT_BOUNDARY)
      idx += 1
      depth += bracket_depth(lines[idx])
    end

    idx
  end

  private def bracket_depth(line : String) : Int32
    (line.count('(') + line.count('{')) - (line.count(')') + line.count('}'))
  end

  private def check_controller_middleware(lines : Array(String), action_line : Int32) : String?
    # Walk backwards to find __construct or class-level middleware
    idx = action_line
    while idx >= 0
      current = lines[idx].strip

      LARAVEL_CONTROLLER_MIDDLEWARE.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      break if current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  private def check_annotations_above(lines : Array(String), method_line : Int32) : String?
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1

      all_patterns = SYMFONY_PATTERNS
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx -= 1
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
  private def check_method_body(lines : Array(String), method_line : Int32) : String?
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
        return desc if stripped.matches?(pattern)
      end

      idx += 1
    end

    nil
  end
end
