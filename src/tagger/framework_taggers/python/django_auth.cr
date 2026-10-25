require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./python_guard_definitions"

@[Noir::TaggerFor(key: "django_auth", name: "Django Auth Tagger", desc: "Identifies Django authentication patterns (decorators, mixins, DRF permissions)", order: 10)]
class DjangoAuthTagger < FrameworkTagger
  include PythonGuardDefinitions

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
  private record PermissionClass, bases : Array(String), has_permission : String?, authenticated_users_only : String?

  # Whatever an anonymous `request.user` fails: `AnonymousUser` is never
  # authenticated, active, staff or superuser, and holds no permissions.
  ANONYMOUS_REFUSING_CHECK = /\b(?:is_authenticated|is_active|is_staff|is_superuser|has_perms?|has_module_perms)\b/

  def initialize(options : Hash(String, YAML::Any))
    super
    @login_required_middleware = false
    @drf_default_permissions = [] of String
    @permission_classes = {} of String => PermissionClass
    @method_def_res = {} of String => Regex
    @dispatch_guards = {} of {String, Int32} => String?
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @login_required_middleware = false
    @drf_default_permissions.clear
    @permission_classes.clear
    @dispatch_guards.clear
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
        flag = class_body(lines, idx).match(/\b(?:self\.)?authenticated_users_only\s*=(?!=)\s*([^\n]+)/).try(&.[1].strip)
        @permission_classes[name] ||= PermissionClass.new(bases, method_body(lines, idx, "has_permission"), flag)
      end
    end
  end

  # The lines of the class body whose header is at `class_idx`.
  private def class_body(lines : Array(String), class_idx : Int32) : String
    class_indent = lines[class_idx].size - lines[class_idx].lstrip.size
    body = [] of String
    ((class_idx + 1)...lines.size).each do |idx|
      current = lines[idx].lstrip
      break if !current.empty? && !current.starts_with?('#') && lines[idx].size - current.size <= class_indent && !current.starts_with?(')')
      body << lines[idx]
    end
    body.join("\n")
  end

  # The body of method `name` in the class whose header is at `class_idx`.
  private def method_body(lines : Array(String), class_idx : Int32, name : String) : String?
    class_indent = lines[class_idx].size - lines[class_idx].lstrip.size
    def_re = @method_def_res[name] ||= /\Adef\s+#{name}\s*\(/
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
        description = check_decorators(lines, line, ctx.path)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end

        # A function view refusing in its own body, or handing this verb to
        # a function that is guarded.
        if guard = body_guard(ctx.path, lines, line, endpoint.method, 0)
          endpoint.add_tag(Tag.new("auth", "Protected by #{guard}", "django_auth"))
          return
        end

        # Check enclosing class for mixins
        description = check_enclosing_class_mixins(lines, line, ctx.path)
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

  private def check_decorators(lines : Array(String), endpoint_line : Int32, path : String) : String?
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
      # A project decorator, judged by what its definition does.
      if current.starts_with?('@') && (guard = decorator_guard(current, path))
        return "Protected by #{guard}"
      end

      idx -= 1
    end

    nil
  end

  # Library decorators are judged by `DECORATOR_PATTERNS` before this is
  # asked; an unresolved name says nothing.
  private def decorator_description(line : String) : String?
    nil
  end

  # Django spells the refusal of an anonymous caller its own way too: the
  # 403 response class, a 401/403 status, `PermissionDenied`, or the login
  # redirect.
  DJANGO_REFUSAL  = /\bHttpResponseForbidden\s*\(|\bredirect_to_login\s*\(|\bstatus\s*=\s*40[13]\b|\braise\s+(?:\w+\.)*PermissionDenied\b/
  ANONYMOUS_TEST  = /\bnot\s+request\.user\.is_authenticated\b|\brequest\.user\.is_anonymous\b/
  METHOD_TEST     = /^(?:if|elif)\b.*(?<![\w.])request\.method\b/
  RETURNED_HELPER = /\breturn\s+([A-Za-z_][\w.]*)\s*\(\s*request\s*[,)]/
  DEF_LINE        = /^(?:async\s+)?def\s/

  private def refuses_caller?(body : String) : Bool
    super || ((body.matches?(CALLER_IDENTITY) || body.matches?(/\bis_anonymous\b/)) && body.matches?(DJANGO_REFUSAL))
  end

  # The guard a function view's own body applies to `method`, read off its
  # top-level statements up to the first unconditional `return`: an
  # `if not request.user.is_authenticated:` block that refuses, or the
  # guard on the function a dispatcher returns for this verb (`if
  # request.method == "POST": return create_check(request)`, a trailing
  # `return get_check(request)` for the verbs no branch took).
  private def body_guard(path : String, lines : Array(String), def_line : Int32, method : String, depth : Int32) : String?
    def_idx = def_line - 1
    return unless (head = lines[def_idx]?) && head.lstrip.matches?(DEF_LINE)
    def_indent = head.size - head.lstrip.size
    idx = def_idx
    parens = 0
    while idx < lines.size
      code = Analyzer::Python::Helper.strip_python_comment(lines[idx]).rstrip
      parens += code.count('(') - code.count(')')
      break if parens <= 0 && code.ends_with?(':')
      idx += 1
    end
    body = [] of {Int32, String}
    ((idx + 1)...lines.size).each do |j|
      code = Analyzer::Python::Helper.strip_python_comment(lines[j]).rstrip
      next if code.strip.empty?
      break if code.size - code.lstrip.size <= def_indent
      body << {code.size - code.lstrip.size, code.strip}
    end
    level = body.first?.try(&.[0]) || return
    method = method.upcase
    branched = Set(String).new
    body.each_with_index do |(indent, code), k|
      next unless indent == level
      block = body[(k + 1)..].take_while { |entry| entry[0] > level }.map(&.[1])
      inline = code.partition(':')[2]
      block.unshift(inline) unless inline.strip.empty?
      if code.starts_with?("if ") && code.matches?(ANONYMOUS_TEST)
        text = block.join('\n')
        return "Django request.user.is_authenticated check" if text.matches?(DJANGO_REFUSAL) || text.matches?(UNAUTHENTICATED) || text.matches?(FORBIDDEN)
      elsif code.matches?(METHOD_TEST)
        test = code.split("request.method", 2)[1]
        next if test.matches?(/\A\s*(?:!=|not\s+in)/)
        verbs = test.partition(':')[0].scan(/['"]([A-Za-z]+)['"]/).map(&.[1].upcase)
        branched.concat(verbs)
        next unless verbs.includes?(method)
        if depth == 0
          block.each do |statement|
            if (helper = statement.match(RETURNED_HELPER)) && (guard = helper_guard(path, helper[1], method))
              return guard
            end
          end
        end
        # This verb may be answered here, before any check below.
        return if block.any?(&.starts_with?("return"))
      elsif code.starts_with?("return")
        if depth == 0 && !branched.includes?(method) && (helper = code.match(RETURNED_HELPER))
          return helper_guard(path, helper[1], method)
        end
        return
      end
    end
    nil
  end

  # The guard on function `name` as `path` refers to it: its decorators,
  # then its own body.
  private def helper_guard(path : String, name : String, method : String) : String?
    site = python_definition_site(path, name) || return
    file, def_name = site
    lines = read_file_lines(file) || return
    def_re = /^(?:async\s+)?def\s+#{Regex.escape(def_name)}\s*\(/
    def_idx = lines.index(&.matches?(def_re)) || return
    if guard = check_decorators(lines, def_idx + 1, file)
      return "#{guard.lchop("Protected by ")} (via #{def_name})"
    end
    body_guard(file, lines, def_idx + 1, method, 1).try { |own| "#{own} (via #{def_name})" }
  end

  private def check_enclosing_class_mixins(lines : Array(String), endpoint_line : Int32, path : String) : String?
    idx = enclosing_class(lines, endpoint_line).try(&.[0]) || return
    # `@method_decorator(..., name=...)` above the class decorates the
    # handler it names (or all of them, via `dispatch`).
    handler = lines[endpoint_line - 1].match(/\bdef\s+(\w+)/).try(&.[1])
    if description = method_decorator_auth(decorator_text(lines, idx + 1), handler)
      return description
    end
    # Its bases, wherever the header wraps.
    header = class_header(lines, idx)
    key = {path, idx}
    guard = @dispatch_guards.has_key?(key) ? @dispatch_guards[key] : (@dispatch_guards[key] = dispatch_guard(path, lines, idx, 0, Set(String).new))
    return "Protected by #{guard}" if guard
    MIXIN_PATTERNS.each do |pattern|
      if header.matches?(pattern)
        mixin_name = pattern.source.gsub("\\", "")
        return "Protected by Django #{mixin_name}"
      end
    end
    nil
  end

  # `AccessMixin.handle_no_permission` sends the caller to the login page
  # or raises `PermissionDenied`.
  NO_PERMISSION = /\bself\.handle_no_permission\s*\(/
  SETTING_READ  = /\bsettings\.([A-Z][A-Z0-9_]*)\b/

  # The guard the `dispatch` of a class-based view applies, walking its
  # project bases depth-first in declaration order (Python's MRO for the
  # usual mixin shapes): the first `dispatch` that turns away a caller who
  # is not logged in, as `Class.dispatch`, naming the setting its test
  # depends on. A `dispatch` that neither refuses nor hands on to `super()`
  # ends its branch, since the bases' never runs. A base the scan does not
  # hold is judged by its name (`MIXIN_PATTERNS`).
  # ponytail: a non-delegating `dispatch` ends only its own branch, not
  # the bases listed after it.
  private def dispatch_guard(path : String, lines : Array(String), class_idx : Int32, depth : Int32,
                             seen : Set(String)) : String?
    return if depth > 8
    name = lines[class_idx].match(/^\s*class\s+(\w+)/).try(&.[1]) || return
    return unless seen.add?("#{path}:#{name}")
    if body = method_body(lines, class_idx, "dispatch")
      if setting = dispatch_refusal(body, path, lines, class_idx)
        return setting.empty? ? "#{name}.dispatch" : "#{name}.dispatch (settings.#{setting} decides; a setting can make it public)"
      end
      return unless body.matches?(/\bsuper\s*\(/)
    end
    class_bases(class_header(lines, class_idx)).each do |base|
      if site = class_site(path, base)
        file, idx = site
        base_lines = read_file_lines(file) || next
        if guard = dispatch_guard(file, base_lines, idx, depth + 1, seen)
          return guard
        end
      elsif pattern = MIXIN_PATTERNS.find { |mixin| base.matches?(mixin) }
        return "Django #{pattern.source.gsub("\\", "")}"
      end
    end
    nil
  end

  # The setting an `if` in a `dispatch` body tests ("" for none) when that
  # `if` reads the caller and its block refuses; nil when none does.
  private def dispatch_refusal(body : String, path : String, lines : Array(String), class_idx : Int32) : String?
    code = body.lines.map { |line| Analyzer::Python::Helper.strip_python_comment(line).rstrip }
    code.each_with_index do |line, k|
      m = line.strip.match(/\A(?:if|elif)\s+(.+?):(.*)\z/) || next
      indent = line.size - line.lstrip.size
      nested = code[(k + 1)..].take_while { |inner| inner.strip.empty? || inner.size - inner.lstrip.size > indent }.reject(&.strip.empty?)
      # Only the block's own statements: a refusal nested deeper (in the
      # `except` of a token check) turns away a bad credential, not the
      # anonymous caller.
      level = nested.min_of? { |inner| inner.size - inner.lstrip.size }
      text = ([m[2]] + nested.select { |inner| inner.size - inner.lstrip.size == level }).join('\n')
      next unless text.matches?(NO_PERMISSION) || text.matches?(DJANGO_REFUSAL) || text.matches?(FORBIDDEN) ||
                  text.matches?(UNAUTHENTICATED) || text.matches?(LOGIN_REDIRECT)
      next unless caller_test?(m[1], path, lines, class_idx)
      return m[1].match(SETTING_READ).try(&.[1]) || ""
    end
    nil
  end

  # Whether condition `cond` reads who the caller is: directly, or through
  # a `self.method()` of the class (or its project bases) that does
  # (`if not self.has_permission():`).
  private def caller_test?(cond : String, path : String, lines : Array(String), class_idx : Int32) : Bool
    return true if cond.matches?(ANONYMOUS_REFUSING_CHECK) || cond.matches?(/\bis_anonymous\b/)
    cond.scan(/\bself\.(\w+)\s*\(/).any? do |call|
      chain_method_body(path, lines, class_idx, call[1], 0).try(&.matches?(ANONYMOUS_REFUSING_CHECK)) || false
    end
  end

  private def chain_method_body(path : String, lines : Array(String), class_idx : Int32, name : String, depth : Int32) : String?
    return if depth > 8
    if body = method_body(lines, class_idx, name)
      return body
    end
    class_bases(class_header(lines, class_idx)).each do |base|
      file, idx = class_site(path, base) || next
      base_lines = read_file_lines(file) || next
      if body = chain_method_body(file, base_lines, idx, name, depth + 1)
        return body
      end
    end
    nil
  end

  # `class X(A, mixins.B, C[T], metaclass=M):` -> ["A", "mixins.B", "C"].
  private def class_bases(header : String) : Array(String)
    open = header.index('(') || return [] of String
    header[(open + 1)..].sub(/\)\s*:[\s\S]*\z/, "").split(',').compact_map do |base|
      base = base.strip
      next if base.includes?('=')
      base.sub(/\[[\s\S]*\z/, "").strip.match(/\A[A-Za-z_][\w.]*\z/).try(&.[0])
    end
  end

  # `{file, line index}` of the class declaration `base` names in `path`.
  private def class_site(path : String, base : String) : {String, Int32}?
    mod, _, leaf = base.rpartition('.')
    site = if mod.empty?
             python_definition_site(path, leaf)
           elsif (target = python_imported_symbols(path)[mod]?) && target[1].empty?
             python_definition_site(target[0], leaf)
           end
    file, name = site || return
    file_lines = read_file_lines(file) || return
    class_re = /^\s*class\s+#{Regex.escape(name)}\b/
    idx = file_lines.index(&.matches?(class_re)) || return
    {file, idx}
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
    verdicts = defaults.map { |perms| permissions_refusal(perms, method) }
    if !verdicts.empty? && verdicts.none?(Nil)
      setting = verdicts.compact.max_by(&.size)
      setting.empty? ? "Protected by DRF DEFAULT_PERMISSION_CLASSES" : "Protected by DRF DEFAULT_PERMISSION_CLASSES (settings.#{setting} decides; a setting can make it public)"
    else
      ""
    end
  end

  private def drf_permission_desc(perms : String, method : String, source : String) : String?
    setting = permissions_refusal(perms, method) || return
    setting.empty? ? "Protected by #{source}" : "Protected by #{source} (settings.#{setting} decides; a setting can make it public)"
  end

  # DRF checks every class in `permission_classes` and refuses when any
  # one does; `A | B` refuses only when both alternatives do, `A & B`
  # when either does. Nil when anonymous gets through; else the setting
  # the refusal depends on ("" for none).
  private def permissions_refusal(perms : String, method : String) : String?
    inner = perms.strip
    inner = inner[1...-1] if inner.size >= 2 && "([".includes?(inner[0])
    verdicts = inner.split(',').compact_map do |entry|
      alternatives = entry.split('|').map(&.strip).reject(&.empty?)
      next if alternatives.empty?
      either = alternatives.map do |alternative|
        alternative.split('&').compact_map { |name| permission_refusal(name.strip(" ()\n\t\"'").split('.').last, method) }.min_by?(&.size)
      end
      next if either.any?(Nil)
      either.compact.max_by(&.size)
    end
    verdicts.min_by?(&.size)
  end

  # Whether permission class `name` refuses an anonymous caller `method`,
  # as `permissions_refusal` reports it. A project class is judged by its
  # `has_permission` (or, when that hands on to `super()`, its bases'),
  # and a DjangoModelPermissions subclass by the `authenticated_users_only`
  # it sets: False lets anonymous through, a setting makes it conditional.
  private def permission_refusal(name : String, method : String, depth = 0) : String?
    return "" if name.matches?(DRF_AUTH_PERMISSION_NAME)
    if name.matches?(DRF_WRITE_ONLY_PERMISSION_NAME)
      return SAFE_METHODS.includes?(method.upcase) ? nil : ""
    end
    return if depth > 4
    klass = @permission_classes[name]? || return
    setting = nil
    if flag = klass.authenticated_users_only
      return if flag == "False"
      setting = flag.match(SETTING_READ).try(&.[1])
    end
    if body = klass.has_permission
      if body.matches?(ANONYMOUS_REFUSING_CHECK)
        # `if request.method in SAFE_METHODS: return True` opens reads.
        return if body.includes?("SAFE_METHODS") && SAFE_METHODS.includes?(method.upcase)
        return body.match(SETTING_READ).try(&.[1]) || ""
      end
      return unless body.matches?(/\bsuper\s*\(\s*\)\s*\.has_permission\b/)
    end
    klass.bases.each do |base|
      if verdict = permission_refusal(base, method, depth + 1)
        return setting || verdict
      end
    end
    nil
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
