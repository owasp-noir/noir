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

  # `@method_decorator(login_required)` on a method, or
  # `@method_decorator([never_cache, login_required], name="dispatch")` on the
  # class. Its argument runs to the next decorator.
  METHOD_DECORATOR      = /@method_decorator\s*\(([^@]*)/
  METHOD_DECORATOR_AUTH = /^\s*\[?\s*(?:[\w.]+\s*,\s*)*(login_required|permission_required|user_passes_test|staff_member_required)\b/
  METHOD_DECORATOR_NAME = /\bname\s*=\s*['"](\w+)['"]/

  MIXIN_PATTERNS = [
    /LoginRequiredMixin/,
    /PermissionRequiredMixin/,
    /UserPassesTestMixin/,
    /StaffMemberRequiredMixin/,
  ]

  # DRF permissions that demand an authenticated caller for every method,
  # and the `...OrReadOnly` ones that only do for unsafe methods.
  DRF_AUTH_PERMISSION_NAME       = /\A(?:IsAuthenticated|IsAdminUser|DjangoModelPermissions|DjangoObjectPermissions)\z/
  DRF_WRITE_ONLY_PERMISSION_NAME = /\A(?:IsAuthenticatedOrReadOnly|DjangoModelPermissionsOrAnonReadOnly)\z/
  SAFE_METHODS                   = %w[GET HEAD OPTIONS]

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

  # A project permission class: its bases and its `has_permission` body
  # (nil when it inherits the method).
  private record PermissionClass, bases : Array(String), has_permission : String?

  # Whatever an anonymous `request.user` fails: `AnonymousUser` is never
  # authenticated, active, staff or superuser, and holds no permissions.
  ANONYMOUS_REFUSING_CHECK = /\b(?:is_authenticated|is_active|is_staff|is_superuser|has_perms?|has_module_perms)\b/

  def initialize(options : Hash(String, YAML::Any))
    super
    @login_required_middleware = false
    @drf_default_permissions = [] of String
    @permission_classes = {} of String => PermissionClass
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @login_required_middleware = false
    @drf_default_permissions.clear
    @permission_classes.clear
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
    scan_permission_classes
  end

  # Every `class X(...Permission...)` in the project, so a custom DRF
  # permission is judged by what its definition does, not by its name.
  private def scan_permission_classes
    collect_files_by_extension(".py").each do |path|
      content = read_file(path)
      next unless content && content.includes?("Permission")
      next if base_relative_path(path).matches?(TEST_OR_DOCS_PATH)
      lines = read_file_lines(path) || next
      lines.each_with_index do |line, idx|
        next unless line.lstrip.starts_with?("class ") && (name = line.match(/^\s*class\s+(\w+)\s*\(/).try(&.[1]))
        header = class_header(lines, idx)
        open = header.index('(') || next
        bases_text = header[(open + 1)..].sub(/\)\s*:[\s\S]*\z/, "")
        next unless bases_text.includes?("Permission")
        bases = bases_text.split(',').map(&.strip.split('.').last.strip).reject(&.empty?)
        @permission_classes[name] ||= PermissionClass.new(bases, method_body(lines, idx, "has_permission"))
      end
    end
  end

  # The body of method `name` in the class whose header is at `class_idx`.
  private def method_body(lines : Array(String), class_idx : Int32, name : String) : String?
    class_indent = lines[class_idx].size - lines[class_idx].lstrip.size
    def_re = /\Adef\s+#{name}\s*\(/
    ((class_idx + 1)...lines.size).each do |idx|
      raw = lines[idx]
      current = raw.lstrip
      next if current.empty? || current.starts_with?('#')
      indent = raw.size - current.size
      break if indent <= class_indent && !current.starts_with?(')')
      next unless current.matches?(def_re)
      body = [] of String
      ((idx + 1)...lines.size).each do |j|
        stripped = lines[j].lstrip
        break if !stripped.empty? && lines[j].size - stripped.size <= indent
        body << lines[j]
      end
      return body.join("\n")
    end
    nil
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
      if description = method_decorator_auth(current, nil)
        return description
      end

      idx -= 1
    end

    nil
  end

  private def check_enclosing_class_mixins(lines : Array(String), endpoint_line : Int32) : String?
    idx = enclosing_class(lines, endpoint_line).try(&.[0]) || return
    # `@method_decorator(..., name=...)` above the class decorates the
    # handler it names (or all of them, via `dispatch`).
    handler = lines[endpoint_line - 1].match(/\bdef\s+(\w+)/).try(&.[1])
    if description = method_decorator_auth(decorator_text(lines, idx + 1), handler)
      return description
    end
    # Its bases, wherever the header wraps.
    header = class_header(lines, idx)
    MIXIN_PATTERNS.each do |pattern|
      if header.matches?(pattern)
        mixin_name = pattern.source.gsub("\\", "")
        return "Protected by Django #{mixin_name}"
      end
    end
    nil
  end

  # The auth decorator a `@method_decorator(...)` in `decorators` wraps, if
  # it reaches `handler`: a class-level one names the method it decorates.
  private def method_decorator_auth(decorators : String, handler : String?) : String?
    decorators.scan(METHOD_DECORATOR) do |m|
      next unless auth = m[1].match(METHOD_DECORATOR_AUTH)
      target = m[1].match(METHOD_DECORATOR_NAME).try(&.[1])
      return "Protected by Django #{auth[1]} decorator" if target.nil? || target == "dispatch" || target == handler
    end
    nil
  end

  # The `class` statement at `idx` through the line that closes its bases:
  # `class WrappedView(\n    LoginRequiredMixin,\n    View,\n):`.
  private def class_header(lines : Array(String), idx : Int32) : String
    String.build do |io|
      depth = 0
      lines[idx, 30].each do |line|
        io << line << ' '
        depth += line.count('(') - line.count(')')
        break if depth <= 0
      end
    end
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
    # A class nested in the body above the method (`class Meta`, a local
    # filter class) is not the one the method belongs to: that one sits
    # at a shallower indent.
    target = lines[idx]
    limit = target.lstrip.starts_with?("class ") ? Int32::MAX : target.size - target.lstrip.size
    while idx >= 0
      raw = lines[idx]
      current = raw.lstrip
      indent = raw.size - current.size
      return {idx, indent} if current.starts_with?("class ") && indent < limit
      return if current.starts_with?("def ") && indent == 0
      idx -= 1
    end
    nil
  end

  # The class-body `permission_classes = ...` value, wherever in the body it
  # sits: a ViewSet route points at the `class` line, above it.
  private def class_permission_classes(lines : Array(String), class_idx : Int32, class_indent : Int32) : String?
    # The body starts after the header, whose closing `):` of a wrapped
    # bases list sits at the class's own indent.
    idx = class_idx
    depth = 0
    while idx < lines.size
      depth += lines[idx].count('(') - lines[idx].count(')')
      idx += 1
      break if depth <= 0
    end
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

  # `{line index, indent}` of each base in `header` that is declared in
  # this same file.
  # ponytail: same file only; a base imported from another module is not read.
  private def same_file_bases(lines : Array(String), header : String) : Array({Int32, Int32})
    open = header.index('(') || return [] of {Int32, Int32}
    names = header[(open + 1)..].sub(/\)\s*:[\s\S]*\z/, "").split(',').compact_map do |base|
      base.strip.sub(/\[[\s\S]*\z/, "").match(/\A[A-Za-z_]\w*\z/).try(&.[0])
    end
    return [] of {Int32, Int32} if names.empty?
    found = [] of {Int32, Int32}
    lines.each_with_index do |line, idx|
      next unless line.includes?("class ") && (m = line.match(/^(\s*)class\s+(\w+)\s*[(:]/))
      found << {idx, m[1].size} if names.includes?(m[2])
    end
    found
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
      # The class, then the bases it inherits from in the same file: a
      # `permission_classes` (or the APIView base) set on a shared mixin
      # applies to every view built on it.
      queue = [klass]
      seen = Set(Int32).new
      while (current = queue.shift?) && seen.size < 8
        class_idx, class_indent = current
        next unless seen.add?(class_idx)
        header = class_header(lines, class_idx)
        drf ||= header.matches?(DRF_VIEW_BASE)
        own ||= class_permission_classes(lines, class_idx, class_indent)
        queue.concat same_file_bases(lines, header)
      end
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
    "Protected by #{source}" if permissions_refuse_anonymous?(perms, method)
  end

  # DRF checks every class in `permission_classes` and refuses when any
  # one does; `A | B` refuses only when both alternatives do, `A & B`
  # when either does.
  private def permissions_refuse_anonymous?(perms : String, method : String) : Bool
    inner = perms.strip
    inner = inner[1...-1] if inner.size >= 2 && "([".includes?(inner[0])
    inner.split(',').any? do |entry|
      alternatives = entry.split('|').map(&.strip).reject(&.empty?)
      !alternatives.empty? && alternatives.all? do |alternative|
        alternative.split('&').any? { |name| permission_refuses_anonymous?(name.strip(" ()\n\t\"'").split('.').last, method) }
      end
    end
  end

  private def permission_refuses_anonymous?(name : String, method : String, depth = 0) : Bool
    return true if name.matches?(DRF_AUTH_PERMISSION_NAME)
    return !SAFE_METHODS.includes?(method.upcase) if name.matches?(DRF_WRITE_ONLY_PERMISSION_NAME)
    return false if depth > 4
    klass = @permission_classes[name]? || return false
    if body = klass.has_permission
      return false unless body.matches?(ANONYMOUS_REFUSING_CHECK)
      # `if request.method in SAFE_METHODS: return True` opens reads.
      return !(body.includes?("SAFE_METHODS") && SAFE_METHODS.includes?(method.upcase))
    end
    klass.bases.any? { |base| permission_refuses_anonymous?(base, method, depth + 1) }
  end

  private def login_not_required?(lines : Array(String), endpoint_line : Int32) : Bool
    return true if decorator_text(lines, endpoint_line).matches?(LOGIN_NOT_REQUIRED)
    if klass = enclosing_class(lines, endpoint_line)
      class_idx = klass[0]
      return true if class_header(lines, class_idx).matches?(LOGIN_NOT_REQUIRED_BASE)
      return true if decorator_text(lines, class_idx + 1).matches?(LOGIN_NOT_REQUIRED)
    end
    false
  end
end
