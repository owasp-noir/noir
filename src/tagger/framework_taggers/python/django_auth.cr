require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "django_auth", name: "Django Auth Tagger", desc: "Identifies Django authentication patterns (decorators, mixins, DRF permissions)", order: 10)]
class DjangoAuthTagger < FrameworkTagger
  DECORATOR_PATTERNS = [
    /\@login_required/,
    /\@permission_required\s*\(/,
    /\@user_passes_test\s*\(/,
    /\@staff_member_required/,
  ]

  MIXIN_PATTERNS = [
    /LoginRequiredMixin/,
    /PermissionRequiredMixin/,
    /UserPassesTestMixin/,
    /StaffMemberRequiredMixin/,
  ]

  # DRF permissions that demand an authenticated caller for every method,
  # and the `...OrReadOnly` ones that only do for unsafe methods.
  DRF_AUTH_PERMISSION       = /\b(?:IsAuthenticated|IsAdminUser|DjangoModelPermissions|DjangoObjectPermissions)\b/
  DRF_WRITE_ONLY_PERMISSION = /\b(?:IsAuthenticatedOrReadOnly|DjangoModelPermissionsOrAnonReadOnly)\b/
  SAFE_METHODS              = %w[GET HEAD OPTIONS]

  # A DRF view: `APIView` / `GenericAPIView` / `ListCreateAPIView` / any
  # `ViewSet`. Only these read `permission_classes`.
  DRF_VIEW_BASE = /\w*(?:APIView|ViewSet)\b/

  # Django 5.1's `LoginRequiredMiddleware` makes every view login-only; these
  # opt out. The built-in login and password-reset views (and subclasses)
  # are marked `login_not_required` by Django itself.
  LOGIN_NOT_REQUIRED      = /\blogin_not_required\b/
  LOGIN_NOT_REQUIRED_BASE = /\b(?:LoginView|PasswordReset\w*View)\b/

  LOGIN_REQUIRED_MIDDLEWARE = "django.contrib.auth.middleware.LoginRequiredMiddleware"
  MIDDLEWARE_ASSIGNMENT     = /^\s*MIDDLEWARE\s*\+?=/m
  # Test settings and docs configure throwaway projects.
  TEST_OR_DOCS_PATH = %r{/(?:tests?|docs?)/|/(?:test_[^/]*|[^/]*_tests?|tests|conftest)\.py\z}

  def self.target_techs : Array(String)
    ["python_django"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @login_required_middleware = false
    @drf_default_permissions = [] of String
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @login_required_middleware = false
    @drf_default_permissions.clear
    scan_settings
    super
  end

  # Project-wide auth defaults from settings: `LoginRequiredMiddleware` in
  # MIDDLEWARE, and REST_FRAMEWORK's `DEFAULT_PERMISSION_CLASSES`. Test and
  # docs settings are skipped, and the middleware counts only inside a
  # `MIDDLEWARE = [...]` / `+= [...]` value, not wherever it is mentioned.
  #
  # Split settings (`base.py`, `dev.py`, `prod.py`) can each set their own
  # DRF default, and which one runs is decided at deploy time. Every value
  # is kept, and the default protects a method only if all of them agree
  # (`check_drf_permissions`), so the answer never depends on file order.
  private def scan_settings
    collect_files_by_extension(".py").each do |path|
      content = read_file(path)
      next unless content
      has_middleware = content.includes?("LoginRequiredMiddleware")
      has_drf_default = content.includes?("DEFAULT_PERMISSION_CLASSES")
      next unless has_middleware || has_drf_default
      next if base_relative_path(path).matches?(TEST_OR_DOCS_PATH)
      code = content.lines.map(&.sub(/#.*/, "")).join("\n")
      if has_middleware && bracketed_values_after(code, MIDDLEWARE_ASSIGNMENT).any?(&.includes?(LOGIN_REQUIRED_MIDDLEWARE))
        @login_required_middleware = true
      end
      if has_drf_default && (perms = bracketed_after(code, /DEFAULT_PERMISSION_CLASSES['"]\s*:/))
        @drf_default_permissions << perms
      end
    end
  end

  # The `[...]` / `(...)` value following every match of `key`.
  private def bracketed_values_after(text : String, key : Regex) : Array(String)
    values = [] of String
    pos = 0
    while match = text.match(key, pos)
      pos = match.end
      if value = bracketed_after(text, key, match.begin)
        values << value
      end
    end
    values
  end

  # The `[...]` / `(...)` value following `key`, across lines.
  private def bracketed_after(text : String, key : Regex, from : Int32 = 0) : String?
    match = text.match(key, from)
    return unless match
    open = text.index(/[\[(]/, match.end)
    return unless open
    depth = 0
    (open...text.size).each do |i|
      case text[i]
      when '[', '(' then depth += 1
      when ']', ')'
        depth -= 1
        return text[open..i] if depth == 0
      end
    end
    nil
  end

  private def check_endpoint(endpoint : Endpoint)
    contexts = read_source_context(endpoint)
    return if contexts.empty?

    contexts.each do |ctx|
      line = ctx.line
      lines = ctx.lines

      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      if line && line >= 1 && line <= lines.size
        # Check decorators by walking backwards from endpoint line
        description = check_decorators(lines, line)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end

        # Check enclosing class for mixins
        description = check_enclosing_class_mixins(lines, line)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end

        # DRF permission_classes (view, action, or settings default)
        description = check_drf_permissions(lines, line, endpoint.method)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth")) unless description.empty?
          return
        end

        # Django 5.1 LoginRequiredMiddleware: login-only unless opted out
        if @login_required_middleware && !login_not_required?(lines, line)
          endpoint.add_tag(Tag.new("auth", "Protected by Django LoginRequiredMiddleware", "django_auth"))
          return
        end
      end
    end
  end

  private def check_decorators(lines : Array(String), endpoint_line : Int32) : String?
    # Walk backwards with no fixed limit — Python decorators stack directly above the def,
    # separated only by other decorators, so we stop at the first blank line or definition.
    idx = endpoint_line - 2 # 0-indexed, one line before
    return if idx < 0

    while idx >= 0
      current = lines[idx].strip
      # Stop at blank lines or other definitions
      break if current.empty?
      break if current.starts_with?("class ") || (current.starts_with?("def ") && idx < endpoint_line - 2)

      DECORATOR_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          decorator_name = current.split("(").first.lstrip('@')
          return "Protected by Django #{decorator_name} decorator"
        end
      end

      idx -= 1
    end

    nil
  end

  private def check_enclosing_class_mixins(lines : Array(String), endpoint_line : Int32) : String?
    # Walk backwards from endpoint line to find the enclosing class definition
    idx = endpoint_line - 1 # 0-indexed
    while idx >= 0
      current = lines[idx].lstrip
      if current.starts_with?("class ") && current.includes?("(")
        # Found the enclosing class — check for mixins
        MIXIN_PATTERNS.each do |pattern|
          if current.matches?(pattern)
            mixin_name = pattern.source.gsub("\\", "")
            return "Protected by Django #{mixin_name}"
          end
        end
        # Found a class but no mixin — stop searching
        return
      end
      # If we hit a top-level def (not indented), we're not in a class
      if current.starts_with?("def ") && lines[idx] == lines[idx].lstrip
        return
      end
      idx -= 1
    end

    nil
  end

  # The decorator lines stacked directly above the `def` at `endpoint_line`.
  private def decorator_text(lines : Array(String), endpoint_line : Int32) : String
    idx = endpoint_line - 2
    stack = [] of String
    while idx >= 0
      current = lines[idx].strip
      break if current.empty? || current.starts_with?("def ") || current.starts_with?("class ")
      stack << current
      idx -= 1
    end
    stack.reverse.join(" ")
  end

  # The class enclosing `endpoint_line` (or declared on it, as a ViewSet
  # route is): its header line index and indentation.
  private def enclosing_class(lines : Array(String), endpoint_line : Int32) : {Int32, Int32}?
    idx = endpoint_line - 1
    while idx >= 0
      raw = lines[idx]
      current = raw.lstrip
      indent = raw.size - current.size
      return {idx, indent} if current.starts_with?("class ")
      return if current.starts_with?("def ") && indent == 0
      idx -= 1
    end
    nil
  end

  # The class-body `permission_classes = ...` value, wherever in the body it
  # sits: a ViewSet route points at the `class` line, above it.
  private def class_permission_classes(lines : Array(String), class_idx : Int32, class_indent : Int32) : String?
    idx = class_idx + 1
    while idx < lines.size
      raw = lines[idx]
      current = raw.lstrip
      unless current.empty? || current.starts_with?('#')
        break if raw.size - current.size <= class_indent
        if current.matches?(/^permission_classes\s*=/)
          return bracketed_after(lines[idx, 20].join("\n"), /permission_classes\s*=/)
        end
      end
      idx += 1
    end
    nil
  end

  # The tag description; "" when the view is DRF but its permissions leave
  # this method open (so nothing else may tag it); nil when DRF has nothing
  # to say about the endpoint.
  private def check_drf_permissions(lines : Array(String), endpoint_line : Int32, method : String) : String?
    decorators = decorator_text(lines, endpoint_line)
    # `@action(..., permission_classes=[...])` / `@permission_classes([...])`
    own = bracketed_after(decorators, /permission_classes\s*[=(]/)
    drf = decorators.includes?("@api_view")
    if !own && (klass = enclosing_class(lines, endpoint_line))
      class_idx, class_indent = klass
      drf ||= lines[class_idx].matches?(DRF_VIEW_BASE)
      own = class_permission_classes(lines, class_idx, class_indent)
    end

    if own
      return drf_permission_desc(own, method, "DRF permission_classes") || (drf ? "" : nil)
    end
    return unless drf
    defaults = @drf_default_permissions
    if !defaults.empty? && defaults.all? { |perms| drf_permission_desc(perms, method, "") }
      "Protected by DRF DEFAULT_PERMISSION_CLASSES"
    else
      ""
    end
  end

  private def drf_permission_desc(perms : String, method : String, source : String) : String?
    if perms.matches?(DRF_AUTH_PERMISSION) ||
       (perms.matches?(DRF_WRITE_ONLY_PERMISSION) && !SAFE_METHODS.includes?(method.upcase))
      "Protected by #{source}"
    end
  end

  private def login_not_required?(lines : Array(String), endpoint_line : Int32) : Bool
    return true if decorator_text(lines, endpoint_line).matches?(LOGIN_NOT_REQUIRED)
    if klass = enclosing_class(lines, endpoint_line)
      class_idx = klass[0]
      return true if lines[class_idx].matches?(LOGIN_NOT_REQUIRED_BASE)
      return true if decorator_text(lines, class_idx + 1).matches?(LOGIN_NOT_REQUIRED)
    end
    false
  end
end
