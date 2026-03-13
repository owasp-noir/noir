require "../../../models/framework_tagger"
require "../../../models/endpoint"

class PhpAuthTagger < FrameworkTagger
  # Laravel middleware patterns
  LARAVEL_ROUTE_MIDDLEWARE = [
    {/->middleware\s*\(\s*['"]auth['"]/, "Laravel auth middleware"},
    {/->middleware\s*\(\s*['"]auth:api['"]/, "Laravel auth:api middleware"},
    {/->middleware\s*\(\s*['"]auth:sanctum['"]/, "Laravel Sanctum auth"},
    {/->middleware\s*\(\s*['"]auth:web['"]/, "Laravel web auth"},
    {/->middleware\s*\(\s*['"]verified['"]/, "Laravel verified middleware"},
    {/->middleware\s*\(\s*\[.*['"]auth['"]/, "Laravel auth middleware"},
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
    {/session_start\s*\(\).*\$_SESSION\[['"]user/, "PHP session auth"},
    {/\$_SERVER\[['"]PHP_AUTH_USER['"]/, "PHP HTTP Basic Auth"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "php_auth"
  end

  def self.target_techs : Array(String)
    ["php_laravel", "php_symfony", "php_cakephp", "php_pure"]
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
      line_idx = line_num - 1

      # Check route-level middleware (Laravel)
      description = check_patterns_near_line(lines, line_idx, LARAVEL_ROUTE_MIDDLEWARE, 3)
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
    start_idx = [line_idx - window, 0].max
    end_idx = [line_idx + window, lines.size - 1].min

    (start_idx..end_idx).each do |idx|
      line = lines[idx]
      patterns.each do |pattern, desc|
        return desc if line.matches?(pattern)
      end
    end

    nil
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

  private def check_method_body(lines : Array(String), method_line : Int32) : String?
    idx = method_line + 1
    end_idx = [method_line + 15, lines.size - 1].min
    brace_count = 0

    while idx <= end_idx
      current = lines[idx]
      stripped = current.strip

      brace_count += current.count('{') - current.count('}')
      break if brace_count < 0

      all_patterns = LARAVEL_AUTH_CHECKS + CAKEPHP_PATTERNS + GENERIC_PATTERNS
      all_patterns.each do |pattern, desc|
        return desc if stripped.matches?(pattern)
      end

      idx += 1
    end

    nil
  end
end
