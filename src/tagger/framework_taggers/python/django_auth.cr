require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./python_guard_definitions"
require "./django_middleware_guard"

@[Noir::TaggerFor(key: "django_auth", name: "Django Auth Tagger", desc: "Identifies Django authentication patterns (decorators, mixins, DRF permissions)", order: 10)]
class DjangoAuthTagger < FrameworkTagger
  include PythonGuardDefinitions
  include DjangoMiddlewareGuard

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
  private record PermissionClass, path : String, bases : Array(String), has_permission : String?, authenticated_users_only : String?

  # Whatever an anonymous `request.user` fails: `AnonymousUser` is never
  # authenticated, active, staff or superuser, and holds no permissions.
  ANONYMOUS_REFUSING_CHECK = /\b(?:is_authenticated|is_active|is_staff|is_superuser|has_perms?|has_module_perms)\b/

  def initialize(options : Hash(String, YAML::Any))
    super
    @login_required_middleware = false
    @drf_default_permissions = [] of String
    @permission_classes = {} of String => Array(PermissionClass)
    @method_def_res = {} of String => Regex
    @dispatch_guards = {} of {String, Int32, String} => String | Symbol?
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @login_required_middleware = false
    @drf_default_permissions.clear
    @permission_classes.clear
    @dispatch_guards.clear
    @mro_cache.clear
    @middlewares.clear
    @settings_lists.clear
    @middleware_guards.clear
    @django_roots.clear
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
      has_middleware_list = content.includes?("MIDDLEWARE")
      has_urlconf = content.includes?("ROOT_URLCONF")
      next unless has_middleware || has_drf_default || has_middleware_list || has_urlconf
      next if base_relative_path(path).matches?(TEST_OR_DOCS_PATH)
      code = content.lines.map(&.sub(/#.*/, "")).join("\n")
      register_django_root(path, code) if has_urlconf
      scan_middleware(path, code) if has_middleware_list && code.matches?(MIDDLEWARE_ASSIGNMENT)
      if has_middleware && bracketed_values_after(code, MIDDLEWARE_ASSIGNMENT).any?(&.includes?(LOGIN_REQUIRED_MIDDLEWARE))
        @login_required_middleware = true
      end
      if has_drf_default && (perms = bracketed_after(code, /DEFAULT_PERMISSION_CLASSES['"]\s*:/))
        @drf_default_permissions << perms
      end
    end
    scan_permission_classes
  end

  # Every `class X(...Permission...)` in the project, and every class that
  # defines `has_permission` whatever it extends (a django-oauth-toolkit
  # `TokenHasScope` subclass), so a custom DRF permission is judged by what
  # its definition does, not by its name.
  private def scan_permission_classes
    collect_files_by_extension(".py").each do |path|
      content = read_file(path)
      next unless content && (content.includes?("Permission") || content.includes?("has_permission"))
      next if base_relative_path(path).matches?(TEST_OR_DOCS_PATH)
      lines = read_file_lines(path) || next
      lines.each_with_index do |line, idx|
        next unless line.lstrip.starts_with?("class ") && (name = line.match(/^\s*class\s+(\w+)\s*\(/).try(&.[1]))
        header = class_header(lines, idx)
        open = header.index('(') || next
        bases_text = header[(open + 1)..].sub(/\)\s*:[\s\S]*\z/, "")
        has_permission = method_body(lines, idx, "has_permission")
        next unless bases_text.includes?("Permission") || has_permission
        bases = bases_text.split(',').map(&.strip.split('.').last.strip).reject(&.empty?)
        flag = class_body(lines, idx).match(/\b(?:self\.)?authenticated_users_only\s*=(?!=)\s*([^\n]+)/).try(&.[1].strip)
        (@permission_classes[name] ||= [] of PermissionClass) << PermissionClass.new(path, bases, has_permission, flag)
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

  # The view's own guards first; a project middleware refusing anonymous
  # requests guards whatever the view leaves open.
  private def check_endpoint(endpoint : Endpoint)
    tagged = endpoint.tags.size
    check_view_guards(endpoint)
    return if endpoint.tags.size > tagged
    if guard = middleware_guard(endpoint)
      endpoint.add_tag(Tag.new("auth", guard, "django_auth"))
    end
  end

  private def check_view_guards(endpoint : Endpoint)
    contexts = read_source_context(endpoint)
    return if contexts.empty?
    # A view served by a base class's method lists the view class itself
    # among its code paths (its `class` line): that class's MRO, not the
    # base's, decides what its `dispatch` and permissions do.
    view_class = contexts.find do |ctx|
      line = ctx.line
      line && line >= 1 && line <= ctx.lines.size && ctx.lines[line - 1].lstrip.starts_with?("class ")
    end

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

        class_ctx = view_class || ctx
        class_line = class_ctx.line || line

        # Check enclosing class for mixins
        description = check_enclosing_class_mixins(class_ctx.lines, class_line, class_ctx.path, endpoint.method)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end

        # DRF permission_classes (view, action, or settings default)
        description = check_drf_permissions(lines, line, endpoint.method, class_ctx.lines, class_line)
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
  private def decorator_description(line : String, file : String) : String?
    nil
  end

  # Django spells the refusal of an anonymous caller its own way too: the
  # 403 response class, a 401/403 status, `PermissionDenied`, or the login
  # redirect.
  DJANGO_REFUSAL = /\bHttpResponseForbidden\s*\(|\bredirect_to_login\s*\(|\bstatus\s*=\s*40[13]\b|\braise\s+(?:\w+\.)*PermissionDenied\b/
  USER_ALIAS     = /\A([A-Za-z_]\w*)\s*=\s*(?:self\.)?request\.user\z/
  # A statement that writes before the check runs, so an anonymous caller
  # gets it done even though the response is refused.
  WRITE_CALL = /\.(?:delete|save)\s*\(|\bobjects\b[^\n]*\.(?:create|update|bulk_create|bulk_update|get_or_create|update_or_create)\s*\(/
  COMPOUND   = /\A(?:if|elif|else|for|while|with|try|except|finally|match|case|async\s+(?:for|with))\b/
  # Refusing an anonymous caller by sending it to the login page.
  LOGIN_REDIRECT  = /\breturn\s+(?:redirect|HttpResponseRedirect)\s*\([^\n]*\blogin/i
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
    # `user = request.user`, then `if not user.is_authenticated:`; a name
    # assigned anywhere else in the function may hold another user.
    aliases = body.compact_map { |indent, statement| statement.match(USER_ALIAS).try(&.[1]) if indent == level }
    aliases.select! { |name| body.count { |_, statement| assigns?(statement, name) } == 1 }
    written = false
    body.each_with_index do |(indent, code), k|
      next unless indent == level
      next if code.matches?(USER_ALIAS)
      block = body[(k + 1)..].take_while { |entry| entry[0] > level }
      if code.starts_with?("if ") && anonymous_test?(code.partition(':')[0], aliases)
        return "Django request.user.is_authenticated check" if !written && refusing_block?(code.partition(':')[2].strip, block)
      elsif code.starts_with?("if ") && signed_in_test?(code.partition(':')[0], aliases)
        # `if request.user.is_authenticated: ... return` then a refusal: the
        # signed-in callers leave inside the block, the rest are refused.
        return "Django request.user.is_authenticated check" if !written && exits?(code.partition(':')[2].strip, block) && refusal_follows?(body, k + 1 + block.size, level)
      elsif code.matches?(METHOD_TEST)
        test = code.split("request.method", 2)[1]
        next if test.matches?(/\A\s*(?:!=|not\s+in)/)
        verbs = test.partition(':')[0].scan(/['"]([A-Za-z]+)['"]/).map(&.[1].upcase)
        branched.concat(verbs)
        next unless verbs.includes?(method)
        statements = block.map(&.[1])
        inline = code.partition(':')[2].strip
        statements.unshift(inline) unless inline.empty?
        if depth == 0
          statements.each do |statement|
            if (helper = statement.match(RETURNED_HELPER)) && (guard = helper_guard(path, helper[1], method))
              return guard
            end
          end
        end
        # This verb may be answered here, before any check below.
        return if statements.any?(&.starts_with?("return"))
      elsif code.starts_with?("return")
        if depth == 0 && !branched.includes?(method) && (helper = code.match(RETURNED_HELPER))
          return helper_guard(path, helper[1], method)
        end
        return
      end
      written ||= code.matches?(WRITE_CALL) || block.any?(&.[1].matches?(WRITE_CALL))
    end
    nil
  end

  # Whether every anonymous caller entering an `if` block is refused: its
  # first top-level `return`/`raise` (or the inline one) refuses, and no
  # nested branch before it returns anything else. A refusal under a
  # further condition (`if strict: return redirect("login")`) leaves the
  # other callers through.
  private def refusing_block?(inline : String, block : Array({Int32, String})) : Bool
    return refusal?(inline) unless inline.empty?
    top = block.first?.try(&.[0]) || return false
    block.each_with_index do |(indent, code), k|
      next unless indent == top
      if code.matches?(COMPOUND)
        nested = block[(k + 1)..].take_while { |entry| entry[0] > top }
        return false if nested.any? { |_, line| line.starts_with?("return") && !refusal?(line) }
        next
      end
      next unless code.starts_with?("return") || code.starts_with?("raise")
      statement = ([code] + block[(k + 1)..].take_while { |entry| entry[0] > top }.map(&.[1])).join('\n')
      return refusal?(statement)
    end
    false
  end

  private def refusal?(text : String) : Bool
    text.matches?(DJANGO_REFUSAL) || text.matches?(UNAUTHENTICATED) || text.matches?(FORBIDDEN) || text.matches?(LOGIN_REDIRECT)
  end

  # Whether statement `code` binds `name` (`name = ...`, `a, name = ...`,
  # `for name in`, `with ... as name`).
  private def assigns?(code : String, name : String) : Bool
    target = code.partition(/(?<![=!<>])=(?!=)/)
    return true if !target[1].empty? && target[0].matches?(/(?<![\w.])#{name}\b(?!\s*[.\[(])/)
    code.matches?(/\A(?:async\s+)?for\s+[^:]*(?<![\w.])#{name}\b[^:]*\sin\s|\bas\s+#{name}\b/)
  end

  # `if not request.user.is_authenticated:` / `if request.user.is_anonymous:`
  # (read off `self.request` in a class view, or a `request.user` alias).
  # `not request.user.is_anonymous` / `not(...)` is the signed-in branch.
  private def anonymous_test?(condition : String, aliases : Array(String)) : Bool
    return false unless condition.includes?("is_authenticated") || condition.includes?("is_anonymous")
    (["(?:self\\.)?request\\.user"] + aliases).any? do |subject|
      next true if condition.matches?(/\bnot\s*\(?\s*(?<![\w.])#{subject}\.is_authenticated\b/)
      condition.matches?(/(?<![\w.])#{subject}\.is_anonymous\b/) && !condition.matches?(/\bnot\s*\(?\s*(?<![\w.])#{subject}\.is_anonymous\b/)
    end
  end

  # A condition only a signed-in caller passes: `request.user.is_authenticated`
  # or `not request.user.is_anonymous`, not widened by `or`.
  private def signed_in_test?(condition : String, aliases : Array(String)) : Bool
    return false unless condition.includes?("is_authenticated") || condition.includes?("is_anonymous")
    return false if condition.matches?(/\bor\b/)
    (["(?:self\\.)?request\\.user"] + aliases).any? do |subject|
      next true if condition.matches?(/\bnot\s*\(?\s*(?<![\w.])#{subject}\.is_anonymous\b/)
      condition.matches?(/(?<![\w.])#{subject}\.is_authenticated\b/) && !condition.matches?(/\bnot\s*\(?\s*(?<![\w.])#{subject}\.is_authenticated\b/)
    end
  end

  # Whether an `if` block always leaves the function: a top-level
  # `return`/`raise` in it (or the inline statement).
  private def exits?(inline : String, block : Array({Int32, String})) : Bool
    return inline.starts_with?("return") || inline.starts_with?("raise") unless inline.empty?
    top = block.first?.try(&.[0]) || return false
    block.any? { |indent, code| indent == top && (code.starts_with?("return") || code.starts_with?("raise")) }
  end

  # Whether the top-level statement at `index` of `body` refuses the caller.
  private def refusal_follows?(body : Array({Int32, String}), index : Int32, level : Int32) : Bool
    indent, code = body[index]? || return false
    return false unless indent == level && (code.starts_with?("return") || code.starts_with?("raise"))
    refusal?(([code] + body[(index + 1)..].take_while { |entry| entry[0] > level }.map(&.[1])).join('\n'))
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

  private def check_enclosing_class_mixins(lines : Array(String), endpoint_line : Int32, path : String, method : String) : String?
    idx = enclosing_class(lines, endpoint_line).try(&.[0]) || return
    # `@method_decorator(..., name=...)` above the class decorates the
    # handler it names (or all of them, via `dispatch`).
    handler = lines[endpoint_line - 1].match(/\bdef\s+(\w+)/).try(&.[1])
    if description = method_decorator_auth(decorator_text(lines, idx + 1), handler)
      return description
    end
    # Its bases, wherever the header wraps.
    header = class_header(lines, idx)
    key = {path, idx, method.upcase}
    verdict = @dispatch_guards.has_key?(key) ? @dispatch_guards[key] : (@dispatch_guards[key] = dispatch_guard(path, lines, idx, method.upcase))
    return "Protected by #{verdict}" if verdict.is_a?(String)
    # The walk saw where the request is served without these mixins.
    return if verdict == :stop
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
  # A framework view whose `dispatch` serves the request without calling
  # `super()` (Django's `View` and its generic views, DRF's `APIView` and
  # viewsets): classes after it in the MRO never see the request.
  FRAMEWORK_VIEW = /(?:View|ViewSet)\z/

  # One class of a view's MRO: a project class (`path`, header line `idx`),
  # or a base the scan does not hold (`path` nil).
  private record MroClass, name : String, path : String?, idx : Int32

  # The guard the `dispatch` of a class-based view applies for `method`,
  # walking its MRO (C3, as Python computes it): the first `dispatch` that
  # turns away a caller who is not logged in, as `Class.dispatch`, naming
  # the setting its test depends on. `:stop` when the walk reaches a
  # `dispatch` that serves the request without passing it on (a project one
  # with no `super()`, a framework view's) before any guard; nil when it
  # found nothing either way. A base the scan does not hold is judged by
  # its name (`MIXIN_PATTERNS`), unless a class overrides
  # `handle_no_permission` with one that does not refuse.
  private def dispatch_guard(path : String, lines : Array(String), class_idx : Int32, method : String) : String | Symbol?
    mro = class_mro(path, lines, class_idx)
    soft = soft_no_permission?(mro)
    mro.each do |klass|
      unless file = klass.path
        if pattern = MIXIN_PATTERNS.find { |mixin| klass.name.matches?(mixin) }
          return soft ? :stop : "Django #{pattern.source.gsub("\\", "")}"
        end
        return :stop if klass.name.matches?(FRAMEWORK_VIEW)
        next
      end
      class_lines = read_file_lines(file) || next
      body = method_body(class_lines, klass.idx, "dispatch") || next
      if setting = dispatch_refusal(body, file, class_lines, klass.idx, method, soft)
        return setting.empty? ? "#{klass.name}.dispatch" : "#{klass.name}.dispatch (settings.#{setting} decides; a setting can make it public)"
      end
      return :stop unless body.matches?(/\bsuper\s*\(/)
    end
    nil
  end

  # Whether the first `handle_no_permission` in the MRO is a project one
  # that lets the caller through instead of refusing.
  private def soft_no_permission?(mro : Array(MroClass)) : Bool
    mro.each do |klass|
      file = klass.path || next
      class_lines = read_file_lines(file) || next
      body = method_body(class_lines, klass.idx, "handle_no_permission") || next
      return !(body.matches?(/\braise\b|\bsuper\s*\(/) || body.matches?(DJANGO_REFUSAL) || body.matches?(LOGIN_REDIRECT) ||
        body.matches?(/\bredirect\s*\(/) || body.matches?(FORBIDDEN))
    end
    false
  end

  @mro_cache = {} of {String, Int32} => Array(MroClass)

  # The class at `class_idx` and its bases in C3 order, project classes
  # resolved across files and package re-exports. Falls back to the
  # depth-first order when the bases admit no C3 order.
  private def class_mro(path : String, lines : Array(String), class_idx : Int32, depth = 0) : Array(MroClass)
    key = {path, class_idx}
    if cached = @mro_cache[key]?
      return cached
    end
    name = lines[class_idx].match(/^\s*class\s+(\w+)/).try(&.[1]) || ""
    own = MroClass.new(name, path, class_idx)
    @mro_cache[key] = [own] # cycle guard
    return [own] if depth > 8
    bases = class_bases(class_header(lines, class_idx)).map do |base|
      if (site = class_site(path, base)) && (base_lines = read_file_lines(site[0]))
        class_mro(site[0], base_lines, site[1], depth + 1)
      else
        [MroClass.new(base.rpartition('.')[2], nil, -1)]
      end
    end
    heads = bases.map(&.first)
    mro = [own] + (c3_merge(bases + [heads]) || bases.flatten.uniq!)
    @mro_cache[key] = mro
  end

  private def c3_merge(seqs : Array(Array(MroClass))) : Array(MroClass)?
    seqs = seqs.map(&.dup).reject(&.empty?)
    merged = [] of MroClass
    until seqs.empty?
      head = seqs.map(&.first).find { |candidate| seqs.none?(&.[1..].includes?(candidate)) } || return
      merged << head
      seqs.each { |seq| seq.shift if seq.first == head }
      seqs.reject!(&.empty?)
    end
    merged
  end

  # The setting an `if` in a `dispatch` body tests ("" for none) when that
  # `if` holds for an anonymous caller of `method` and its block refuses;
  # nil when none does.
  private def dispatch_refusal(body : String, path : String, lines : Array(String), class_idx : Int32,
                               method : String, soft : Bool) : String?
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
      refuses = (!soft && text.matches?(NO_PERMISSION)) || text.matches?(DJANGO_REFUSAL) || text.matches?(FORBIDDEN) ||
                text.matches?(UNAUTHENTICATED) || text.matches?(LOGIN_REDIRECT)
      next unless refuses
      if setting = anonymous_condition(m[1], method, path, lines, class_idx)
        return setting
      end
    end
    nil
  end

  NEGATED_IDENTITY  = /\Anot\s+[\w.]*\b(?:is_authenticated|is_active|is_staff|is_superuser)\b|\Anot\s+[\w.]*\bhas_(?:module_)?perms?\s*\(/
  POSITIVE_IDENTITY = /\b(?:is_authenticated|is_active|is_staff|is_superuser|has_perms?|has_module_perms)\b/
  METHOD_CONDITION  = /\Arequest\.method\s*(==|!=|not\s+in|in)\s*(.+)\z/

  # Whether `cond` holds for an anonymous caller of `method`: "" when it
  # does, the setting it also tests when one decides, nil when it does not
  # hold or this cannot tell. A disjunct holds when each of its conjuncts
  # does: a negated identity test (`not request.user.is_authenticated`,
  # `not self.has_permission()`), `is_anonymous`, a verb test naming
  # `method`, or a setting; a positive identity test fails for anonymous.
  private def anonymous_condition(cond : String, method : String, path : String, lines : Array(String), class_idx : Int32) : String?
    # Grouping parentheses are not parsed; a verb tuple is no grouping.
    return if cond.gsub(/\bin\s*\([^()]*\)/, "in _").matches?(/(?:\A|[\s!])\(/)
    cond.split(/\s+or\s+/).each do |disjunct|
      setting = ""
      anonymous = false
      holds = disjunct.split(/\s+and\s+/).all? do |conjunct|
        conjunct = conjunct.strip
        if conjunct.matches?(/\bis_anonymous\b/)
          anonymous = !conjunct.starts_with?("not ")
        elsif conjunct.matches?(NEGATED_IDENTITY)
          anonymous = true
        elsif (call = conjunct.match(/\Anot\s+self\.(\w+)\s*\(/)) &&
              chain_method_body(path, lines, class_idx, call[1], 0).try(&.matches?(ANONYMOUS_REFUSING_CHECK))
          anonymous = true
        elsif conjunct.matches?(POSITIVE_IDENTITY) || conjunct.matches?(/\bself\.\w+\s*\(/)
          false
        elsif verb = conjunct.match(METHOD_CONDITION)
          verbs = verb[2].scan(/['"](\w+)['"]/).map(&.[1].upcase)
          next false if verbs.empty?
          verb[1].in?("==", "in") ? verbs.includes?(method) : !verbs.includes?(method)
        elsif conjunct.includes?("request.method")
          false
        elsif named = conjunct.match(SETTING_READ)
          setting = named[1]
          true
        else
          true
        end
      end
      return setting if holds && anonymous
    end
    nil
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

  # The module file `name` binds in `path` (`from views import generic`),
  # tried from each enclosing directory outward. A binding back to `path`
  # itself is skipped: `shop/views.py` importing `views` means the
  # top-level `views` package, not itself.
  private def imported_module(path : String, name : String) : String?
    content = read_file(path) || return
    dir = File.dirname(path)
    while @base_paths.any? { |base| Noir::PathScope.under_root?(dir, base) }
      if (target = Noir::ImportGraph::Python.find_imported_symbols(dir, path, content)[name]?) &&
         target[1].empty? && target[0] != path
        return target[0]
      end
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    nil
  end

  # `{file, line index}` of the class declaration `base` names in `path`.
  private def class_site(path : String, base : String) : {String, Int32}?
    mod, _, leaf = base.rpartition('.')
    site = if mod.empty?
             python_definition_site(path, leaf)
           elsif module_file = imported_module(path, mod)
             python_definition_site(module_file, leaf)
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
  private def check_drf_permissions(lines : Array(String), endpoint_line : Int32, method : String,
                                    class_lines : Array(String) = lines, class_line : Int32 = endpoint_line) : String?
    decorators = decorator_text(lines, endpoint_line)
    # `@action(..., permission_classes=[...])` / `@permission_classes([...])`
    own = bracketed_after(decorators, /permission_classes\s*[=(]/)
    drf = decorators.includes?("@api_view")
    lines = class_lines
    if !own && (klass = enclosing_class(class_lines, class_line))
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
  # one does, and composes classes with `~`, `&` and `|` (binding in that
  # order, parentheses grouping): `A | B` refuses only when both
  # alternatives do, `A & B` when either does, and `~A` is not judged.
  # Nil when anonymous gets through; else the setting the refusal depends
  # on ("" for none).
  private def permissions_refusal(perms : String, method : String) : String?
    # Settings name classes by dotted path in quotes.
    tokens = perms.gsub(/"([^"\n]*)"|'([^'\n]*)'/) { " #{$1? || $2?} " }.scan(/[A-Za-z_][\w.]*|[&|~()\[\],]/).map(&.[0])
    perm_any(tokens, 0, method)[0]
  end

  private def perm_any(tokens : Array(String), pos : Int32, method : String) : {String?, Int32}
    verdict, pos = perm_all(tokens, pos, method)
    verdicts = [verdict]
    while tokens[pos]? == "|"
      verdict, pos = perm_all(tokens, pos + 1, method)
      verdicts << verdict
    end
    {verdicts.any?(Nil) ? nil : verdicts.compact.max_by(&.size), pos}
  end

  # `&`, and the commas between `permission_classes` entries.
  private def perm_all(tokens : Array(String), pos : Int32, method : String) : {String?, Int32}
    verdict, pos = perm_atom(tokens, pos, method)
    verdicts = [verdict]
    while tokens[pos]?.in?("&", ",")
      pos += 1
      break if tokens[pos]?.nil? || tokens[pos].in?(")", "]")
      verdict, pos = perm_atom(tokens, pos, method)
      verdicts << verdict
    end
    {verdicts.compact.min_by?(&.size), pos}
  end

  private def perm_atom(tokens : Array(String), pos : Int32, method : String) : {String?, Int32}
    case token = tokens[pos]?
    when nil, ")", "]", "&", "|", "," then {nil, pos}
    when "~"                          then {nil, perm_atom(tokens, pos + 1, method)[1]}
    when "(", "["
      verdict, pos = perm_any(tokens, pos + 1, method)
      pos += 1 if tokens[pos]?.in?(")", "]")
      {verdict, pos}
    else
      pos += 1
      # An instance (`HasScope()`): its arguments are not the expression.
      if tokens[pos]? == "("
        depth = 0
        while pos < tokens.size
          depth += 1 if tokens[pos] == "("
          depth -= 1 if tokens[pos] == ")"
          pos += 1
          break if depth == 0
        end
      end
      {permission_refusal(token.split('.').last, method), pos}
    end
  end

  # Whether permission class `name` refuses an anonymous caller `method`,
  # as `permissions_refusal` reports it. A project class is judged by its
  # `has_permission` (or, when that hands on to `super()`, its bases'),
  # and a DjangoModelPermissions subclass by the `authenticated_users_only`
  # it sets: False lets anonymous through, a setting makes it conditional.
  EARLY_ALLOW = /^[ \t]*if[ \t]+([^\n]+?):[ \t]*(?:\n[ \t]*)?return[ \t]+True\b/m

  private def permission_refusal(name : String, method : String, depth = 0) : String?
    return "" if name.matches?(DRF_AUTH_PERMISSION_NAME)
    if name.matches?(DRF_WRITE_ONLY_PERMISSION_NAME)
      return SAFE_METHODS.includes?(method.upcase) ? nil : ""
    end
    return if depth > 4
    candidates = @permission_classes[name]? || return
    # Two project classes sharing the name: only a verdict they agree on.
    verdicts = candidates.map { |klass| class_refusal(klass, method, depth) }.uniq!
    verdicts.size == 1 ? verdicts.first : nil
  end

  private def class_refusal(klass : PermissionClass, method : String, depth : Int32) : String?
    setting = nil
    if (body = klass.has_permission) && (verdict = return_verdict(klass, body, method, depth))
      return verdict.f? ? "" : nil
    end
    if body = klass.has_permission
      # `if request.method in SAFE_METHODS: return True` opens reads; `if
      # not settings.LOGIN_REQUIRED: return True` makes the rest conditional.
      body.scan(EARLY_ALLOW) do |allow|
        cond = allow[1]
        return if cond.includes?("SAFE_METHODS") && !cond.matches?(/\bnot\s+in\b/) && SAFE_METHODS.includes?(method.upcase)
        setting ||= cond.match(SETTING_READ).try(&.[1])
      end
      if body.matches?(ANONYMOUS_REFUSING_CHECK) || refusing_helper_call?(klass.path, body)
        return if body.includes?("SAFE_METHODS") && SAFE_METHODS.includes?(method.upcase)
        return setting || body.match(SETTING_READ).try(&.[1]) || ""
      end
      return unless body.matches?(/\bsuper\s*\(\s*\)\s*\.has_permission\b/)
    end
    # DjangoModelPermissions refuses anonymous callers only while
    # `authenticated_users_only` holds.
    if flag = klass.authenticated_users_only
      return if flag == "False"
      setting ||= flag.match(SETTING_READ).try(&.[1])
    end
    klass.bases.each do |base|
      if verdict = permission_refusal(base, method, depth + 1)
        return setting || verdict
      end
    end
    nil
  end

  # A helper that turns an anonymous caller away before anything lets it
  # through: `if not request.user.is_authenticated: return False`.
  ANONYMOUS_EARLY_REFUSAL = /^[ \t]*if[ \t]+(?:not[ \t]+[\w.]*\buser\.is_authenticated|[\w.]*\buser\.is_anonymous)\b(?:[ \t]+or\b[^:\n]*)?[ \t]*:[ \t]*(?:\n[ \t]*)?(?:return[ \t]+False\b|raise\b)/m

  # A `has_permission` that is a single `return` of a boolean expression
  # calling a project helper (`return (in_group(request, ["guest"]) and
  # request.method in SAFE_METHODS) or in_group(request, ["user"])`),
  # evaluated for an anonymous caller of `method`: F when it refuses, T or
  # Unknown when it may let the caller through. Nil when the body is any
  # other shape, which the readers below judge.
  private def return_verdict(klass : PermissionClass, body : String, method : String, depth : Int32) : MwTri?
    code = [] of String
    pending = ""
    body.each_line do |line|
      line = Analyzer::Python::Helper.strip_python_comment(line).strip
      next if line.empty?
      pending = pending.empty? ? line : "#{pending} #{line}"
      next if mw_mask(pending)[1] > 0
      code << pending
      pending = ""
    end
    returned = code.last?.try(&.match(/\Areturn\s+(.+)\z/)).try(&.[1]) || return
    # Only plain assignments may come before it.
    return unless code[0...-1].all?(&.matches?(/\A\w+\s*=(?!=)/))
    calls = returned.scan(/(?<![\w.])([A-Za-z_]\w*)\s*\(/).map(&.[1])
    return unless calls.any? { |name| resolve_def(klass.path, name) }
    perm_bool(returned, klass, method, depth)
  end

  private def perm_bool(expr : String, klass : PermissionClass, method : String, depth : Int32) : MwTri
    expr = expr.strip
    while expr.starts_with?('(') && mw_mask(expr)[0].index(')') == expr.size - 1
      expr = expr[1...-1].strip
    end
    masked = mw_mask(expr)[0]
    {/\s+or\s+/, /\s+and\s+/}.each_with_index do |word, kind|
      parts = mw_split(expr, masked, word)
      next if parts.size < 2
      values = parts.map { |part| perm_bool(part, klass, method, depth) }
      return kind == 0 ? mw_or(values) : mw_and(values)
    end
    return mw_not(perm_bool(expr[4..], klass, method, depth)) if masked.matches?(/\Anot\s/)
    if verb = expr.match(/\Arequest\.method(?:\.upper\(\))?\s*(==|!=|not\s+in|in)\s*(.+)\z/)
      verbs = verb[2].strip == "SAFE_METHODS" ? SAFE_METHODS : mw_literals(verb[2]).map(&.upcase)
      hit = verbs.includes?(method.upcase)
      return (verb[1] == "==" || verb[1] == "in") == hit ? MwTri::T : MwTri::F
    end
    return MwTri::F if expr.matches?(/\A[\w.]*\buser\.(?:is_authenticated|is_staff|is_superuser|is_active)\z/)
    if expr.matches?(/\Asuper\s*\(\s*\)\s*\.has_permission\s*\(/)
      return klass.bases.any? { |base| permission_refusal(base, method, depth + 1) } ? MwTri::F : MwTri::Unknown
    end
    if expr.matches?(/\A[A-Za-z_]\w*\s*\(/) && refusing_helper_call?(klass.path, "return #{expr}")
      return MwTri::F
    end
    MwTri::Unknown
  end

  # Whether `body` (a `has_permission` in `file`) is nothing but `return
  # helper(...)` of a project function that refuses an anonymous caller
  # first: `return has_group_permission(request, ["user"])`. A call that
  # is one alternative (`helper(...) or view.action == "list"`) or sits
  # under a verb branch decides nothing on its own.
  private def refusing_helper_call?(file : String, body : String) : Bool
    code = body.lines.map { |line| Analyzer::Python::Helper.strip_python_comment(line).strip }.reject(&.empty?).join(' ')
    call = code.match(/\Areturn\s+([A-Za-z_][\w.]*)\s*\(/) || return false
    depth = 0
    code.each_char_with_index do |char, idx|
      next if idx < call.end - 1
      depth += 1 if char == '('
      depth -= 1 if char == ')'
      return false if depth == 0 && idx != code.size - 1
    end
    target = resolve_def(file, call[1]) || return false
    helper = python_defs(target[0])[target[1]]
    !!(match = helper.match(ANONYMOUS_EARLY_REFUSAL)) && !helper[0, match.begin].matches?(/\breturn[ \t]+True\b/)
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
