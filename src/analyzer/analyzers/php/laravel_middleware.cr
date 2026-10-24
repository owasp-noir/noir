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

    MIDDLEWARE_ARG_RE   = /(?:(?:->|::)middleware\s*\(\s*|['"]middleware['"]\s*=>\s*)(\[[^\]]*\]|['"][^'"]+['"])/
    MIDDLEWARE_ENTRY_RE = /['"]([^'"]+)['"]|(\\?[A-Za-z_][\w\\]*)::class/
    ALIAS_ENTRY_RE      = /['"]([\w.-]+)['"]\s*=>\s*(\\?[A-Za-z_][\w\\]*)::class/
    GROUP_EDIT_RE       = /->\s*(?:appendToGroup|prependToGroup|group)\s*\(\s*['"]([\w-]+)['"]\s*,\s*(\[[^\]]*\]|\\?[\w\\]+::class)/
    GROUP_SHORTHAND_RE  = /->\s*(web|api)\s*\(/

    # Middleware names a route-wiring group's prelude applies.
    private def middleware_names(prelude : String) : Array(String)
      names = [] of String
      prelude.scan(MIDDLEWARE_ARG_RE) { |m| names.concat(middleware_entries(m[1], EMPTY_IMPORTS, nil)) }
      names
    end

    # The routes file's guard: the first of the names it is loaded under that
    # is a known auth alias or a group/alias judged to authenticate.
    private def route_file_guard(path : String, names : Array(String)) : String?
      return if names.empty?
      guards = @middleware_guards[composer_project_root(path)]?
      names.each do |name|
        return "Laravel #{name} middleware" if name.matches?(AUTH_ALIAS_RE)
        guards.try(&.[name]?).try { |desc| return desc }
      end
      nil
    end

    # Skeleton default when no wiring names the file: an app root serves
    # `routes/web.php` under `web` and `routes/api.php` under `api`.
    private def default_route_file_middleware(path : String) : Array(String)
      group = path.ends_with?("/routes/api.php") ? "api" : (path.ends_with?("/routes/web.php") ? "web" : nil)
      return [] of String unless group
      root = File.dirname(File.dirname(path))
      File.exists?(File.join(root, "artisan")) || File.exists?(File.join(root, "bootstrap", "app.php")) ? [group] : [] of String
    end

    # ponytail: any `->withoutMiddleware(...)` on the route drops the file's
    # guard, whatever it names; compare names if that ever hides a real guard.
    private def tag_file_guard(endpoint : Endpoint, guard : String?, statement : String) : Nil
      return unless guard
      return if statement.includes?("withoutMiddleware")
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
            next unless middleware_refuses?(klass, root)
            guards[name] ||= "Laravel '#{name}' middleware (#{klass.split('\\').last})"
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

    private def qualify_class(ref : String, imports : Hash(String, String), namespace : String?) : String
      return ref.lchop('\\') if ref.starts_with?('\\')
      head, _, rest = ref.partition('\\')
      if mapped = imports[head]?
        mapped = mapped.lchop('\\')
        return rest.empty? ? mapped : "#{mapped}\\#{rest}"
      end
      namespace ? "#{namespace}\\#{ref}" : ref
    end

    # Why a group entry guards, or nil: a built-in auth alias, an alias to a
    # refusing class, or a refusing class.
    private def entry_guard(entry : String, root : String, aliases : Hash(String, String)) : String?
      return entry if entry.matches?(AUTH_ALIAS_RE)
      klass = aliases[entry.split(':', 2)[0]]? || (entry.includes?('\\') ? entry : nil)
      klass.split('\\').last if klass && middleware_refuses?(klass, root)
    end

    # Whether the middleware class's `handle()` (or the `$this->` helpers it
    # calls, or the parent it defers to) can refuse the caller.
    private def middleware_refuses?(fqcn : String, root : String, depth : Int32 = 0) : Bool
      return true if KNOWN_AUTH_MIDDLEWARE.includes?(fqcn)
      return false if depth > 2
      segments = fqcn.split('\\')
      return false unless segments.size >= 2
      path = File.join(root, "app", "#{segments[1..].join("/")}.php")
      return false unless File.exists?(path)

      content = php_code(read_file_content(path))
      parent = content.match(/\bclass\s+\w+\s+extends\s+(\\?[\w\\]+)/).try do |m|
        qualify_class(m[1], parse_use_imports(content), content.match(/\bnamespace\s+([\w\\]+)\s*;/).try(&.[1]))
      end
      handle = content.match(/(?:public|protected|private)\s+function\s+handle\s*\(/)
      return parent ? middleware_refuses?(parent, root, depth + 1) : false unless handle
      body = extract_php_method_body_after(content, handle.begin(0)).try(&.[0])
      return false unless body

      bodies = [body]
      body.scan(THIS_CALL_RE).map(&.[1]).uniq!.each do |name|
        next unless sig = content.match(/(?:public|protected|private)\s+(?:static\s+)?function\s+#{name}\s*\(/)
        extract_php_method_body_after(content, sig.begin(0)).try { |helper| bodies << helper[0] }
      end
      return true if bodies.any?(&.matches?(MIDDLEWARE_REFUSAL_RE))
      !!parent && body.includes?("parent::handle") && middleware_refuses?(parent, root, depth + 1)
    end
  end
end
