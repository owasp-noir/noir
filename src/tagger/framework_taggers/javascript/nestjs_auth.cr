require "../../../models/framework_tagger"
require "../../../models/endpoint"

class NestjsAuthTagger < FrameworkTagger
  # NestJS guard decorators
  GUARD_PATTERNS = [
    {/\@UseGuards\s*\(\s*AuthGuard/, "NestJS @UseGuards(AuthGuard)"},
    {/\@UseGuards\s*\(\s*JwtAuthGuard/, "NestJS @UseGuards(JwtAuthGuard)"},
    {/\@UseGuards\s*\(\s*LocalAuthGuard/, "NestJS @UseGuards(LocalAuthGuard)"},
    {/\@UseGuards\s*\(\s*RolesGuard/, "NestJS @UseGuards(RolesGuard)"},
    {/\@UseGuards\s*\(\s*AuthenticationGuard/, "NestJS @UseGuards(AuthenticationGuard)"},
    {/\@UseGuards\s*\(\s*\w*[Aa]uth\w*Guard/, "NestJS auth guard"},
    {/\@UseGuards\s*\(\s*GqlAuthGuard/, "NestJS GraphQL auth guard"},
  ]

  # NestJS role/permission decorators
  ROLE_PATTERNS = [
    {/\@Roles\s*\(/, "NestJS @Roles decorator"},
    {/\@Permissions\s*\(/, "NestJS @Permissions decorator"},
    {/\@RequirePermissions\s*\(/, "NestJS @RequirePermissions decorator"},
    {/\@SetMetadata\s*\(\s*['"]roles['"]/, "NestJS role metadata"},
  ]

  # NestJS auth-related decorators
  AUTH_DECORATORS = [
    {/\@ApiBearerAuth\s*\(/, "NestJS @ApiBearerAuth (Swagger)"},
    {/\@ApiBasicAuth\s*\(/, "NestJS @ApiBasicAuth (Swagger)"},
    {/\@ApiOAuth2\s*\(/, "NestJS @ApiOAuth2 (Swagger)"},
    {/\@ApiSecurity\s*\(/, "NestJS @ApiSecurity (Swagger)"},
  ]

  # Public/skip auth markers (negative signal)
  PUBLIC_PATTERNS = [
    /\@Public\s*\(\)/,
    /\@SkipAuth\s*\(\)/,
    /\@AllowAnonymous\s*\(\)/,
    /\@SetMetadata\s*\(\s*['"]isPublic['"]/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "nestjs_auth"
    @class_guards = Hash(String, String).new
  end

  def self.target_techs : Array(String)
    ["js_nestjs", "ts_nestjs"]
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

      # Check if endpoint is explicitly public
      if public?(lines, line_idx)
        return
      end

      # Check method-level guards/decorators
      description = check_method_decorators(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "nestjs_auth"))
        return
      end

      # Check class-level guards (applies to all methods)
      description = check_class_decorators(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description} (class-level)", "nestjs_auth"))
        return
      end
    end
  end

  private def public?(lines : Array(String), method_line : Int32) : Bool
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1

      PUBLIC_PATTERNS.each do |pattern|
        return true if current.matches?(pattern)
      end

      idx -= 1
    end

    false
  end

  private def check_method_decorators(lines : Array(String), method_line : Int32) : String?
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      # Stop if we hit another method
      break if current.includes?("async ") && current.includes?("(") && idx < method_line - 1

      all_patterns = GUARD_PATTERNS + ROLE_PATTERNS + AUTH_DECORATORS
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx -= 1
    end

    nil
  end

  private def check_class_decorators(lines : Array(String), method_line : Int32) : String?
    # Walk backwards to find the class definition, checking for class-level guards
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.includes?("class ") && current.includes?("{")
        # Found class — now check decorators above it
        class_idx = idx - 1
        while class_idx >= 0 && class_idx >= idx - 10
          decorator = lines[class_idx].strip
          break if decorator.empty? && class_idx < idx - 1

          GUARD_PATTERNS.each do |pattern, desc|
            return desc if decorator.matches?(pattern)
          end

          class_idx -= 1
        end
        break
      end

      idx -= 1
    end

    nil
  end
end
