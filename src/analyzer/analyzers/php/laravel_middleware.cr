require "json"
require "../../engines/php_engine"

# Laravel middleware groups and aliases, read from where the app defines
# them, judged by what their `handle()` does.
#
# A route file is loaded under a middleware group (`Route::middleware('api')
# ->group(base_path('routes/api.php'))`, `withRouting(api: ...)`), and the
# group's members come from `app/Http/Kernel.php` `$middlewareGroups`
# (Laravel <= 10) or `bootstrap/app.php` `->withMiddleware(...)` (11+). None
# of that is visible from the route file, so every route in `routes/api.php`
# used to read as anonymous however the `api` group authenticated.
module Analyzer::Php
  class Laravel < PhpEngine
    # Middleware group or alias name -> what makes it a guard, per project root.
    alias MiddlewareGuards = Hash(String, String)

    # Framework classes whose definition lives in vendor/.
    KNOWN_AUTH_MIDDLEWARE = Set{
      "Illuminate\\Auth\\Middleware\\Authenticate",
      "Illuminate\\Auth\\Middleware\\AuthenticateWithBasicAuth",
    }
    # The built-in `auth` / `auth:sanctum` / `auth.basic` aliases.
    AUTH_ALIAS_RE = /\Aauth(?:\.basic)?(?::|\z)/

    # What a `handle()` that can refuse the caller does: abort / throw / answer
    # with 401 or 403, throw an auth exception, authenticate (which throws
    # `AuthenticationException`), or send the guest to the login page.
    MIDDLEWARE_REFUSAL_RE = /\babort(?:_if|_unless)?\s*\([^;]*?\b40[13]\b|\bthrow\s+new\s+\\?(?:[\w\\]*\\)?\w*(?:Auth|Unauthori[sz]ed|AccessDenied|Forbidden)\w*\s*\(|\bthrow\s+new\s+[^;]*?\b40[13]\b|->\s*authenticate\s*\(|\bAuth::authenticate\s*\(|\bredirect\(\s*\)\s*->\s*guest\s*\(|\bRedirect::guest\s*\(|\broute\(\s*['"]login['"]|\bredirect\s*\(\s*['"]\/?login\b|\b(?:response\s*\(|->\s*json\s*\()[^;]*?\b40[13]\b|HTTP_(?:UNAUTHORIZED|FORBIDDEN)\b/

    # The names a `->middleware(...)` call or `'middleware' =>` attribute
    # gives: an array, or one or more strings / `Foo::class` arguments.
    MIDDLEWARE_NAME_ARG = %q((?:['"][^'"]+['"]|\\?[A-Za-z_][\w\\]*::class))
    MIDDLEWARE_ARG_RE   = /(?:(?:->|::)middleware\s*\(\s*|['"]middleware['"]\s*=>\s*)(\[[^\]]*\]|#{MIDDLEWARE_NAME_ARG}(?:\s*[,.]\s*#{MIDDLEWARE_NAME_ARG})*)/
    MIDDLEWARE_ENTRY_RE = /['"]([^'"]+)['"]|(\\?[A-Za-z_][\w\\]*)::class/
    ALIAS_ENTRY_RE      = /['"]([\w.-]+)['"]\s*=>\s*(\\?[A-Za-z_][\w\\]*)::class/
    GROUP_EDIT_RE       = /->\s*(?:appendToGroup|prependToGroup|group)\s*\(\s*['"]([\w-]+)['"]\s*,\s*(\[[^\]]*\]|\\?[\w\\]+::class)/
    GROUP_SHORTHAND_RE  = /->\s*(web|api)\s*\(/

    # Middleware names a route-wiring group's prelude applies.
    # Class entries (`Foo::class`) are qualified through `imports`.
    private def middleware_names(prelude : String, imports : Hash(String, String) = EMPTY_IMPORTS) : Array(String)
      names = [] of String
      prelude.scan(MIDDLEWARE_ARG_RE) { |m| names.concat(middleware_entries(m[1], imports, nil)) }
      names
    end

    # The guard among `names`: the first that is a known auth alias, a
    # group/alias judged to authenticate, or a middleware class (named
    # directly, `->middleware(Foo::class)`) whose definition can refuse.
    private def route_guard(path : String, names : Array(String)) : String?
      return if names.empty?
      root = composer_project_root(path)
      guards = @middleware_guards[root]?
      names.each do |name|
        return "Laravel #{name} middleware" if name.matches?(AUTH_ALIAS_RE)
        guards.try(&.[name]?).try { |desc| return desc }
        next unless name.includes?('\\') && (note = class_middleware_refusal(name, root))
        return "Laravel #{name.split('\\').last} middleware#{note.empty? ? "" : " (#{note})"}"
      end
      nil
    end

    @class_middleware_refusals = {} of String => String?
    @class_middleware_mutex = Mutex.new

    # `middleware_refusal`, once per class: every route of a group asks.
    private def class_middleware_refusal(fqcn : String, root : String) : String?
      key = "#{root}\0#{fqcn}"
      @class_middleware_mutex.synchronize do
        return @class_middleware_refusals[key] if @class_middleware_refusals.has_key?(key)
      end
      refusal = middleware_refusal(fqcn, root)
      @class_middleware_mutex.synchronize { @class_middleware_refusals[key] = refusal }
    end

    # Skeleton default when no wiring names the file: an app root serves
    # `routes/web.php` under `web` and `routes/api.php` under `api`.
    private def default_route_file_middleware(path : String) : Array(String)
      group = path.ends_with?("/routes/api.php") ? "api" : (path.ends_with?("/routes/web.php") ? "web" : nil)
      return [] of String unless group
      root = File.dirname(File.dirname(path))
      File.exists?(File.join(root, "artisan")) || File.exists?(File.join(root, "bootstrap", "app.php")) ? [group] : [] of String
    end

    WITHOUT_MIDDLEWARE_RE = /->\s*withoutMiddleware\s*\(\s*(\[[^\]]*\]|['"][^'"]+['"])?/

    # Tag the guard of a route loaded under `names` (route file, then its
    # enclosing groups) whose own registration is `statement`. As in Laravel,
    # the statement adds its `->middleware(...)` / `'middleware' =>` names and
    # `->withoutMiddleware(...)` takes names away.
    private def tag_route_guard(endpoint : Endpoint, path : String, names : Array(String), statement : String, imports : Hash(String, String) = EMPTY_IMPORTS) : Nil
      names += middleware_names(statement, imports) if statement.includes?("iddleware")
      if statement.includes?("withoutMiddleware")
        statement.scan(WITHOUT_MIDDLEWARE_RE) do |m|
          # ponytail: a class, an unreadable list, or a guarding name the route
          # was not given by name may be a member of one of its groups; drop
          # every guard rather than guess which.
          return unless list = m[1]?
          return if list.includes?("::class")
          withdrawn = middleware_entries(list, EMPTY_IMPORTS, nil)
          return if withdrawn.any? { |name| !names.includes?(name) && route_guard(path, [name]) }
          names -= withdrawn
        end
      end
      return unless guard = route_guard(path, names)
      endpoint.add_tag(Tag.new("auth", "Protected by #{guard}", "php_auth"))
    end

    private def collect_middleware_guards : Hash(String, MiddlewareGuards)
      result = {} of String => MiddlewareGuards
      php_source_files.each do |path|
        next unless path.ends_with?("/Http/Kernel.php") || path.ends_with?("/bootstrap/app.php")
        next if PhpEngine.test_path?(base_relative_path(path))
        begin
          content = read_file_content(path)
          next unless content.includes?("iddleware")
          content = php_code(content)
          root = composer_project_root(path)
          imports = parse_use_imports(content)
          namespace = content.match(/\bnamespace\s+([\w\\]+)\s*;/).try(&.[1])
          groups, aliases = middleware_definitions(content, imports, namespace)
          guards = result[root] ||= MiddlewareGuards.new
          aliases.each do |name, klass|
            next unless note = middleware_refusal(klass, root)
            guards[name] ||= "Laravel '#{name}' middleware (#{with_note(klass.split('\\').last, note)})"
          end
          groups.each do |name, entries|
            entries.each do |entry|
              next unless desc = entry_guard(entry, root, aliases)
              guards[name] ||= "Laravel '#{name}' middleware group (#{desc})"
              break
            end
          end
        rescue e
          logger.debug "Error reading Laravel middleware #{path}: #{e}"
        end
      end
      result
    end

    # {group name -> entries, alias -> class}, entries qualified.
    private def middleware_definitions(content : String, imports : Hash(String, String), namespace : String?) : Tuple(Hash(String, Array(String)), Hash(String, String))
      groups = Hash(String, Array(String)).new
      aliases = {} of String => String

      if (m = content.match(/\$middlewareGroups\s*=\s*\[/)) && (array = literal_array_at(content, m.end(0) - 1))
        array.scan(/['"]([\w-]+)['"]\s*=>\s*\[/) do |key|
          array_entry(array, key[1]).try { |entries| (groups[key[1]] ||= [] of String).concat(middleware_entries(entries, imports, namespace)) }
        end
      end
      if (m = content.match(/\$(?:middlewareAliases|routeMiddleware)\s*=\s*\[/)) && (array = literal_array_at(content, m.end(0) - 1))
        array.scan(ALIAS_ENTRY_RE) { |e| aliases[e[1]] = qualify_class(e[2], imports, namespace) }
      end

      # Laravel 11+ `->withMiddleware(function (Middleware $middleware) { ... })`.
      if content.includes?("withMiddleware")
        lexer = Noir::PhpLexer.new(content)
        content.scan(GROUP_SHORTHAND_RE) do |call|
          next unless close = lexer.matching_delimiter(call.end(0) - 1)
          args = content[call.end(0)...close]
          args.scan(/\b(?:append|prepend)\s*:\s*(\[[^\]]*\]|\\?[\w\\]+::class)/) do |list|
            (groups[call[1]] ||= [] of String).concat(middleware_entries(list[1], imports, namespace))
          end
        end
        content.scan(GROUP_EDIT_RE) { |edit| (groups[edit[1]] ||= [] of String).concat(middleware_entries(edit[2], imports, namespace)) }
        content.scan(/->\s*alias\s*\(\s*\[([^\]]*)\]/) do |list|
          list[1].scan(ALIAS_ENTRY_RE) { |e| aliases[e[1]] = qualify_class(e[2], imports, namespace) }
        end
      end
      {groups, aliases}
    end

    private def middleware_entries(text : String, imports : Hash(String, String), namespace : String?) : Array(String)
      text.scan(MIDDLEWARE_ENTRY_RE).map { |m| m[1]? || qualify_class(m[2], imports, namespace) }
    end

    # Why a group entry guards, or nil: a built-in auth alias, an alias to a
    # refusing class, or a refusing class.
    private def entry_guard(entry : String, root : String, aliases : Hash(String, String)) : String?
      return entry if entry.matches?(AUTH_ALIAS_RE)
      klass = aliases[entry.split(':', 2)[0]]? || (entry.includes?('\\') ? entry : nil)
      return unless klass && (note = middleware_refusal(klass, root))
      with_note(klass.split('\\').last, note)
    end

    private def with_note(text : String, note : String) : String
      note.empty? ? text : "#{text}; #{note}"
    end

    # Why a refusal is not unconditional: it only happens under an
    # environment or config check.
    SETTING_NOTE            = "an environment or config check decides; a setting can make it public"
    ENV_CONDITION_RE        = /\b(?:app\s*\(\s*\)\s*->|App::|\$this->app\s*->)\s*(?:environment|isLocal|isProduction|runningUnitTests|runningInConsole|isDownForMaintenance)\s*\(|\bconfig\s*\(|\bConfig::get\s*\(|\benv\s*\(/
    CREDENTIAL_CONDITION_RE = /\buser\s*\(|\bauth(?:::|\s*\()|->\s*(?:check|guest|tokenCan|can|cannot|hasValid\w*Signature)\s*\(|token|password|api_?key|signature|credential/i
    # A request-shape check (CORS origin, preflight method, host), not a
    # check on who the caller is.
    ORIGIN_CONDITION_RE = /['"](?:origin|referer|host)['"]|->\s*(?:isMethod|getMethod|method|getHost)\s*\(/i
    IF_RE               = /\b(?:else\s*)?if\s*\(/
    ELSE_BLOCK_RE       = /\G\s*else\s*\{/

    # Whether the middleware class's `handle()` (or the `$this->` helpers it
    # calls, or the parent it defers to) can refuse the caller: nil when it
    # cannot, "" when it refuses unconditionally, `SETTING_NOTE` when only an
    # environment or config check stands between the caller and a refusal.
    private def middleware_refusal(fqcn : String, root : String, depth : Int32 = 0) : String?
      return "" if KNOWN_AUTH_MIDDLEWARE.includes?(fqcn)
      return if depth > 2
      return unless (path = app_class_path(fqcn, root)) && File.exists?(path)

      content = php_code(read_file_content(path))
      parent = content.match(/\bclass\s+\w+\s+extends\s+(\\?[\w\\]+)/).try do |m|
        qualify_class(m[1], parse_use_imports(content), content.match(/\bnamespace\s+([\w\\]+)\s*;/).try(&.[1]))
      end
      handle = content.match(/(?:public|protected|private)\s+function\s+handle\s*\(/)
      return parent ? middleware_refusal(parent, root, depth + 1) : nil unless handle
      body = extract_php_method_body_after(content, handle.begin(0)).try(&.[0])
      return unless body

      helpers = {} of String => String
      body.scan(THIS_CALL_RE).map(&.[1]).uniq!.each do |name|
        next unless sig = content.match(/(?:public|protected|private)\s+(?:static\s+)?function\s+#{name}\s*\(/)
        next unless helper = extract_php_method_body_after(content, sig.begin(0))
        refusal_verdict(helper[0], helpers).try { |verdict| helpers[name] = verdict }
      end
      verdicts = [refusal_verdict(body, helpers)]
      verdicts << middleware_refusal(parent, root, depth + 1) if parent && body.includes?("parent::handle")
      verdicts.includes?("") ? "" : verdicts.compact.first?
    end

    # The refusals in one method body (strings and comments are not code),
    # judged by the conditions around them: under an environment/config
    # check it is a setting (and no guard at all unless the check is also
    # about the caller's identity); under a request-shape check alone
    # (CORS origin, preflight) it does not concern the caller's identity.
    # A call to a `helpers` entry is a refusal of that helper's kind.
    private def refusal_verdict(body : String, helpers : Hash(String, String)) : String?
      lexer = Noir::PhpLexer.new(body, php_mode: true)
      points = [] of Tuple(Int32, String, String)
      body.scan(MIDDLEWARE_REFUSAL_RE) { |m| points << {m.begin(0), m[0], ""} if lexer.in_code?(m.begin(0)) }
      body.scan(THIS_CALL_RE) do |m|
        next unless (note = helpers[m[1]]?) && lexer.in_code?(m.begin(0))
        points << {m.begin(0), "", note}
      end
      return if points.empty?

      conditions = condition_blocks(body, lexer)
      verdict = nil
      points.each do |(at, text, note)|
        around = conditions.select(&.[1].includes?(at)).map(&.[0]).push(text).join(' ')
        # `if (app()->isLocal()) { return $next($request); }` before the refusal.
        skipped = conditions.any? { |(cond, block)| block.end <= at && cond.matches?(ENV_CONDITION_RE) && body[block].includes?("$next(") }
        if around.matches?(ENV_CONDITION_RE)
          verdict = SETTING_NOTE if around.matches?(CREDENTIAL_CONDITION_RE)
        elsif around.matches?(ORIGIN_CONDITION_RE) && !around.matches?(CREDENTIAL_CONDITION_RE)
          next
        elsif skipped || !note.empty?
          verdict = SETTING_NOTE
        else
          return ""
        end
      end
      verdict
    end

    # {condition, block it guards} for every `if` / `elseif` in `body`; an
    # `else` block is listed under its `if`'s condition too.
    private def condition_blocks(body : String, lexer : Noir::PhpLexer) : Array(Tuple(String, Range(Int32, Int32)))
      blocks = [] of Tuple(String, Range(Int32, Int32))
      body.scan(IF_RE) do |m|
        open = m.end(0) - 1
        next unless lexer.in_code?(open) && (close = lexer.matching_delimiter(open))
        cond = body[(open + 1)...close]
        start = close + 1
        while start < body.size && lexer.masked[start].whitespace?
          start += 1
        end
        next unless start < body.size
        stop = lexer.masked[start] == '{' ? lexer.matching_delimiter(start) : lexer.statement_end(start)
        next unless stop
        blocks << {cond, start...stop}
        if (other = body.match(ELSE_BLOCK_RE, stop + 1)) && (other_end = lexer.matching_delimiter(other.end(0) - 1))
          blocks << {cond, other.end(0)...other_end}
        end
      end
      blocks
    end

    @psr4_prefixes = {} of String => Array(Tuple(String, String))

    # The file PSR-4 maps an app class to: the project's `composer.json`
    # `autoload.psr-4` prefixes (Laravel's `App\` => `app/` when it lists
    # none). nil for anything outside them, such as a vendor class.
    private def app_class_path(fqcn : String, root : String) : String?
      fqcn = fqcn.lchop('\\')
      prefixes = @class_middleware_mutex.synchronize { @psr4_prefixes[root]? } || begin
        found = composer_psr4_prefixes(root)
        @class_middleware_mutex.synchronize { @psr4_prefixes[root] = found }
      end
      prefixes.each do |(namespace, dir)|
        next unless fqcn.starts_with?(namespace) && fqcn.size > namespace.size
        return File.join(root, dir, "#{fqcn[namespace.size..].gsub('\\', '/')}.php")
      end
      nil
    end

    private def composer_psr4_prefixes(root : String) : Array(Tuple(String, String))
      prefixes = [] of Tuple(String, String)
      composer = File.join(root, "composer.json")
      if File.exists?(composer)
        begin
          JSON.parse(read_file_content(composer))["autoload"]?.try(&.["psr-4"]?).try(&.as_h?).try &.each do |namespace, dirs|
            dir = dirs.as_s? || dirs.as_a?.try(&.first?).try(&.as_s?)
            prefixes << {namespace.ends_with?('\\') ? namespace : "#{namespace}\\", dir} if dir && !namespace.empty?
          end
        rescue JSON::ParseException
        end
      end
      prefixes << {"App\\", "app/"} if prefixes.empty?
      prefixes.sort_by! { |(namespace, _)| -namespace.size }
    end
  end
end
