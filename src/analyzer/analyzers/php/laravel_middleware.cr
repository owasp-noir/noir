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

    EMPTY_ARRAYS = {} of String => LiteralArray
    # `->middleware($middleware)` / `'middleware' => $middleware`: a variable
    # handed whole as the list.
    MIDDLEWARE_VAR_RE = /((?:->|::)middleware\s*\(\s*|['"]middleware['"]\s*=>\s*)\$(\w+)\b(?!\s*(?:\[|->|\(|::))/

    # `text` with each middleware variable replaced by the literal list it
    # holds at `at` (`$middleware = ['auth:sanctum'];` at file scope, or one
    # a group closure captured with `use ($middleware)`), so the names read
    # like a written-out list. A variable the scan cannot prove constant
    # stays as written and names nothing.
    private def expand_middleware_vars(text : String, arrays : Hash(String, LiteralArray), at : Int32) : String
      return text if arrays.empty? || !text.includes?('$')
      text.gsub(MIDDLEWARE_VAR_RE) do |whole, m|
        array = arrays[m[2]]?
        next whole unless array && array.pos < at && array.entries.all?(&.key.nil?)
        "#{m[1]}[#{array.entries.join(", ", &.value)}]"
      end
    end

    # The arrays visible at `at`: none inside a function body of the content
    # (its own scope, where a parameter may shadow the name).
    private def scoped_arrays(arrays : Hash(String, LiteralArray), scopes : Array(Range(Int32, Int32)), at : Int32) : Hash(String, LiteralArray)
      scopes.any?(&.includes?(at)) ? EMPTY_ARRAYS : arrays
    end

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
    # One a setting can lift yields to a later one no setting can.
    private def route_guard(path : String, names : Array(String)) : String?
      return if names.empty?
      root = composer_project_root(path)
      guards = @middleware_guards[root]?
      lifted = nil
      names.each do |name|
        desc = if name.matches?(AUTH_ALIAS_RE)
                 "Laravel #{name} middleware"
               elsif found = guards.try(&.[name]?)
                 found
               elsif name.includes?('\\') && (note = class_middleware_refusal(name, root))
                 "Laravel #{name.split('\\').last} middleware#{note.empty? ? "" : " (#{note})"}"
               end
        next unless desc
        return desc unless lifted?(desc)
        lifted ||= desc
      end
      lifted
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
    # enclosing groups) whose own registration is `statement`, with its
    # controller constructor's middleware and the handler's own `check`:
    # the first no setting or condition can lift, else the first at all.
    private def tag_route_guard(endpoint : Endpoint, path : String, names : Array(String), statement : String, imports : Hash(String, String) = EMPTY_IMPORTS,
                                arrays : Hash(String, LiteralArray) = EMPTY_ARRAYS, at : Int32 = 0, check : String? = nil,
                                controller : Array(CtorName) = NO_CTOR_NAMES) : Nil
      firm = controller.compact_map { |(name, note)| name unless note }
      statement = expand_middleware_vars(statement, arrays, at)
      candidates = [statement_guard(path, names + firm, statement, imports), check]
      controller.each do |(name, note)|
        next unless note && (desc = route_guard(path, [name]))
        candidates << "#{desc} (controller constructor: #{note})"
      end
      found = candidates.compact
      guard = found.find { |desc| !lifted?(desc) } || found.first?
      endpoint.add_tag(Tag.new("auth", "Protected by #{guard}", "php_auth")) if guard
      # `can:` is the `Authorize` middleware: `Gate::authorize` answers 403
      # when the ability is denied.
      # ponytail: a `->withoutMiddleware('can:...')` on the route is not subtracted.
      ability = (names + firm).find(&.starts_with?("can:"))
      ability ||= middleware_names(statement, imports).find(&.starts_with?("can:")) if statement.includes?("can:")
      endpoint.add_tag(Tag.new("authz", "Protected by Laravel #{ability} middleware", "php_auth")) if ability
    end

    # A guard a setting or a condition can lift: it may not stand.
    private def lifted?(desc : String) : Bool
      desc.includes?(SETTING_NOTE) || desc.includes?(CONDITION_NOTE)
    end

    # As in Laravel, the statement adds its `->middleware(...)` /
    # `'middleware' =>` names and `->withoutMiddleware(...)` takes names away.
    private def statement_guard(path : String, names : Array(String), statement : String, imports : Hash(String, String)) : String?
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
      route_guard(path, names)
    end

    # A constructor middleware name, with why it may not apply (nil: it
    # applies to the action).
    alias CtorName = Tuple(String, String?)
    NO_CTOR_NAMES = [] of CtorName

    # One `$this->middleware(...)` call in a controller constructor: its
    # names, the actions `only` / `except` limit it to (nil: no limit), and
    # `note` when the call is conditional or its limit unreadable.
    private record ControllerMiddleware, names : Array(String), only : Array(String)?, except : Array(String)?, note : String?

    @controller_middleware = {} of String => Array(ControllerMiddleware)
    CTOR_MIDDLEWARE_RE  = /\$this\s*->\s*middleware\s*\(/
    PARENT_CTOR_RE      = /\bparent::__construct\s*\(/
    CLOSURE_ARG_RE      = /\A\s*(?:static\s+)?(?:function|fn)\b/
    CTOR_FILTER_CALL_RE = /->\s*(only|except)\s*\(/
    CTOR_OPTION_RE      = /\A\[\s*['"](only|except)['"]\s*=>\s*(\[[^\[\]$]*\]|['"][^'"$]*['"])\s*,?\s*\]\z/
    CONDITION_NOTE      = "a condition decides whether it applies"
    FILTER_NOTE         = "its only/except list is not readable, so it may not apply to this action; a condition decides whether it applies"

    # Middleware names the routed controller's constructor (its own, or
    # the one it inherits) applies to `action`. Read once per controller.
    private def constructor_middleware(controller_path : String, action : String, routes_file_path : String) : Array(CtorName)
      entries = @class_middleware_mutex.synchronize { @controller_middleware[controller_path]? } || begin
        found = read_constructor_middleware(controller_path, routes_file_path)
        @class_middleware_mutex.synchronize { @controller_middleware[controller_path] = found }
      end
      action = action.downcase
      entries.compact_map do |entry|
        next if entry.only.try(&.includes?(action)) == false || entry.except.try(&.includes?(action))
        entry.names.map { |name| {name, entry.note} }
      end.flatten
    end

    # The constructor's `$this->middleware('auth')`,
    # `->middleware(Foo::class)->except([...])` and
    # `->middleware('auth', ['except' => [...]])` calls, plus the parent's
    # when it calls `parent::__construct()`. A closure middleware is not a
    # name; a call under a condition (braced or not) or with an unreadable
    # limit carries a note.
    private def read_constructor_middleware(controller_path : String, routes_file_path : String, depth : Int32 = 0) : Array(ControllerMiddleware)
      list = [] of ControllerMiddleware
      return list if depth > 3
      return list unless found = find_action(controller_path, "__construct", routes_file_path)
      source, signature, ctor_file = found
      return list unless body = method_body(source, signature).try(&.[0])
      return list unless body.includes?("middleware") || body.includes?("parent::")
      namespace = source.offsets.content.match(NAMESPACE_DECL_RE).try(&.[1])
      lexer = Noir::PhpLexer.new(body, php_mode: true)
      conditions = condition_blocks(body, lexer)
      body.scan(CTOR_MIDDLEWARE_RE) do |m|
        open = m.end(0) - 1
        next unless lexer.in_code?(m.begin(0)) && (close = lexer.matching_delimiter(open))
        args = top_level_args(lexer, body, open + 1, close)
        next if args.empty? || args[0].matches?(CLOSURE_ARG_RE)
        names = middleware_entries(args[0], source.imports, namespace)
        next if names.empty?
        note = statement_condition(body, lexer, conditions, m.begin(0))
        only = except = nil
        unreadable = args.size > 2
        if options = args[1]?
          if option = options.gsub(/\s+/, " ").match(CTOR_OPTION_RE)
            option[1] == "only" ? (only = literal_names(option[2])) : (except = literal_names(option[2]))
          else
            unreadable = true
          end
        end
        tail = body[(close + 1)...lexer.statement_end(close + 1)]
        tail.scan(CTOR_FILTER_CALL_RE) do |call|
          filter_close = Noir::PhpLexer.new(tail, php_mode: true).matching_delimiter(call.end(0) - 1)
          list_text = filter_close ? tail[call.end(0)...filter_close] : "$"
          if list_text.includes?('$') || !list_text.matches?(/['"]/)
            unreadable = true
          else
            call[1] == "only" ? (only = literal_names(list_text)) : (except = literal_names(list_text))
          end
        end
        note ||= FILTER_NOTE if unreadable
        list << ControllerMiddleware.new(names, unreadable ? nil : only, unreadable ? nil : except, note)
      end
      body.scan(PARENT_CTOR_RE) do |m|
        next unless lexer.in_code?(m.begin(0)) && (parent = parent_class_file(ctor_file, routes_file_path))
        note = statement_condition(body, lexer, conditions, m.begin(0))
        read_constructor_middleware(parent, routes_file_path, depth + 1).each do |entry|
          list << (note ? entry.copy_with(note: entry.note || note) : entry)
        end
      end
      list
    end

    private def literal_names(text : String) : Array(String)
      text.scan(/['"]([^'"]+)['"]/).map(&.[1].downcase)
    end

    # Why a statement starting at `pos` of a method body may not run: nil
    # when it is a top-level statement, the setting note under an
    # environment/config check, the condition note under any other `if`,
    # loop or block (braced or a single-statement body).
    private def statement_condition(body : String, lexer : Noir::PhpLexer, conditions : Array(Tuple(String, Range(Int32, Int32))), pos : Int32) : String?
      enclosing = conditions.select(&.[1].includes?(pos))
      return enclosing.any?(&.[0].matches?(ENV_CONDITION_RE)) ? SETTING_NOTE : CONDITION_NOTE unless enclosing.empty?
      depth = 0
      (0...pos).each do |i|
        case lexer.masked[i]
        when '{' then depth += 1
        when '}' then depth -= 1
        end
      end
      return CONDITION_NOTE unless depth == 0
      i = pos - 1
      while i >= 0 && (lexer.masked[i].whitespace? || !lexer.in_code?(i))
        i -= 1
      end
      i < 0 || lexer.masked[i] == ';' || lexer.masked[i] == '}' ? nil : CONDITION_NOTE
    end

    # A handler that refuses an anonymous caller before doing anything: a
    # top-level `abort_if(!$request->user(), 403)` /
    # `abort_unless(auth()->check(), 404)`, or `if (!Auth::check()) {
    # abort(403); }` (also on a `$user = $request->user()` it read first),
    # before it does anything else.
    USER_CHECK_RE  = /\G(?:abort_(if|unless)|if)\s*\(/
    GUARD_ARG      = /(?:['"]\w+['"]|\$\w+)?/.source
    USER_SOURCE    = /(?:\$request\s*->\s*user\s*\(\s*#{GUARD_ARG}\s*\)|(?:auth\s*\(\s*#{GUARD_ARG}\s*\)|Auth::guard\s*\(\s*#{GUARD_ARG}\s*\)|auth\s*\(\s*\)\s*->\s*guard\s*\(\s*#{GUARD_ARG}\s*\))\s*->\s*(?:user|check)\s*\(\s*\)|Auth::(?:user|check)\s*\(\s*\))/.source
    USER_SOURCE_RE = /\A#{USER_SOURCE}\z/
    USER_GUEST_RE  = /\A(?:auth\s*\(\s*\)\s*->\s*guest|Auth::guest)\s*\(\s*\)\z/
    USER_ASSIGN_RE = /\G\$(\w+)\s*=\s*#{USER_SOURCE}\s*;/
    # What an `if (!user)` block does to refuse: abort, throw, redirect, or
    # answer 401/403.
    BLOCK_REFUSAL_RE = /\A(?:abort\s*\(|throw\b|return\s+(?:redirect\b|Redirect::)|return\s+response\s*\([^;]*?\b40[13]\b|return\s+response\s*\(\s*\)\s*->\s*json\s*\([^;]*?\b40[13]\b)/
    COMPOUND_RE      = /\A(?:if|else|try|foreach|for|while|switch|do|match)\b/

    # Whether the block (or single statement) from `start` to `stop` refuses
    # before anything else could answer: one of its top-level statements
    # refuses, and none before it returns or branches (a nested `if` or
    # `try` that may answer first).
    private def block_refuses?(lexer : Noir::PhpLexer, start : Int32, stop : Int32) : Bool
      return lexer.masked[start...stop].join.strip.matches?(BLOCK_REFUSAL_RE) unless lexer.masked[start] == '{'
      pos = start + 1
      while pos < stop
        while pos < stop && (lexer.masked[pos].whitespace? || !lexer.in_code?(pos))
          pos += 1
        end
        return false unless pos < stop
        stmt_end = Math.min(lexer.statement_end(pos), stop)
        text = lexer.masked[pos...stmt_end].join.strip
        return true if text.matches?(BLOCK_REFUSAL_RE)
        return false if text.matches?(COMPOUND_RE) || text.matches?(/\b(?:return|yield|exit|die)\b/) || text.includes?('{')
        pos = Math.max(stmt_end, pos + 1)
      end
      false
    end

    # Validating the input first refuses rather than serves (422).
    VALIDATE_STATEMENT_RE = /\G(?:\$\w+\s*=\s*)?(?:\$this|\$request)\s*->\s*validate(?:WithBag)?\s*\(/

    # Only the handler's leading statements count: reading the user,
    # validating input, then checks. Anything else first (work, a return, a condition that is not
    # about the user) and a later check no longer stands in front of it.
    private def handler_user_check(body : String) : String?
      return unless body.includes?("abort") || body.includes?("if")
      lexer = Noir::PhpLexer.new(body, php_mode: true)
      users = [] of String
      pos = 0
      loop do
        while pos < body.size && (lexer.masked[pos].whitespace? || !lexer.in_code?(pos))
          pos += 1
        end
        return unless pos < body.size
        if assign = body.match(USER_ASSIGN_RE, pos)
          users << assign[1]
          pos = assign.end(0)
          next
        end
        if body.match(VALIDATE_STATEMENT_RE, pos)
          pos = lexer.statement_end(pos)
          next
        end
        return unless m = body.match(USER_CHECK_RE, pos)
        open = m.end(0) - 1
        return unless close = lexer.matching_delimiter(open)
        if m[1]?
          condition = body[(open + 1)...lexer.expression_end(open + 1)]
          refuses = m[1] == "if" ? user_missing?(condition, users) : split_condition(condition, "&&").any? { |part| user_source?(part, users) }
          return "Laravel handler check (#{body[m.begin(0)..close].gsub(/\s+/, " ")})" if refuses
          pos = Math.max(lexer.statement_end(close + 1), close + 1)
        else
          return unless user_missing?(body[(open + 1)...close], users)
          start = close + 1
          while start < body.size && lexer.masked[start].whitespace?
            start += 1
          end
          return unless start < body.size
          stop = lexer.masked[start] == '{' ? lexer.matching_delimiter(start) : lexer.statement_end(start)
          return unless stop && block_refuses?(lexer, start, stop)
          return "Laravel handler check (if (#{body[(open + 1)...close].strip.gsub(/\s+/, " ")}) refuses)"
        end
      end
    end

    # Whether `condition` holds when no user is signed in: one of its
    # top-level `||` parts is `!<user>` or `<auth>->guest()`.
    private def user_missing?(condition : String, users : Array(String) = [] of String) : Bool
      split_condition(condition.strip, "||").any? do |part|
        part.matches?(USER_GUEST_RE) || ((negated = part.lchop?('!')) && user_source?(negated, users)) || false
      end
    end

    private def user_source?(expr : String, users : Array(String)) : Bool
      expr = expr.strip
      while expr.starts_with?('(') && expr.ends_with?(')')
        expr = expr[1...-1].strip
      end
      expr.matches?(USER_SOURCE_RE) || ((var = expr.match(/\A\$(\w+)\z/)) && users.includes?(var[1])) || false
    end

    # `condition` split on a top-level `||` / `&&` (not one inside a call).
    private def split_condition(condition : String, op : String) : Array(String)
      parts = [] of String
      depth = 0
      start = 0
      i = 0
      while i < condition.size
        case condition[i]
        when '(', '[' then depth += 1
        when ')', ']' then depth -= 1
        end
        if depth == 0 && condition[i, 2] == op
          parts << condition[start...i].strip
          start = i + 2
          i += 1
        end
        i += 1
      end
      parts << condition[start..].strip
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
    # A refusal that is about the caller's identity by its own words.
    IDENTITY_REFUSAL_RE = /authenticat|\bguest\s*\(|\bAuth\w*Exception|Unauthori[sz]edHttpException/i
    # A request-shape check (CORS origin, preflight method, host), not a
    # check on who the caller is.
    ORIGIN_CONDITION_RE = /['"](?:origin|referer|host)['"]|->\s*(?:isMethod|getMethod|method|getHost)\s*\(/i
    IF_RE               = /\b(?:else\s*)?if\s*\(/
    REDIRECT_RE         = /\breturn\s+(?:redirect\b|Redirect::)/
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
      redirects = body.scan(REDIRECT_RE).select { |m| lexer.in_code?(m.begin(0)) }
      return if points.empty? && redirects.empty?

      conditions = condition_blocks(body, lexer)
      # A redirect anywhere (home, a locale) is not a refusal; one under a
      # check that the caller is not signed in sends the guest away.
      redirects.each do |m|
        innermost = conditions.select(&.[1].includes?(m.begin(0))).min_by?(&.[1].size)
        next unless innermost && user_missing?(innermost[0])
        points << {m.begin(0), m[0], ""}
      end
      return if points.empty?
      verdict = nil
      body_checks_caller = body.matches?(CREDENTIAL_CONDITION_RE)
      points.each do |(at, text, note)|
        identity_evidence = body_checks_caller || text.matches?(IDENTITY_REFUSAL_RE)
        around = conditions.select(&.[1].includes?(at)).map(&.[0]).push(text).join(' ')
        # `if (app()->isLocal()) { return $next($request); }` before the refusal.
        skipped = conditions.any? { |(cond, block)| block.end <= at && cond.matches?(ENV_CONDITION_RE) && body[block].includes?("$next(") }
        if around.matches?(ENV_CONDITION_RE)
          verdict = SETTING_NOTE if around.matches?(CREDENTIAL_CONDITION_RE)
        elsif around.matches?(ORIGIN_CONDITION_RE) && !around.matches?(CREDENTIAL_CONDITION_RE)
          next
        elsif skipped && note.empty? && !identity_evidence
          # `if (!config('x.enabled')) return $next($request);` then a refusal
          # that never looks at who the caller is: it refuses everyone (or no
          # one) by app state, so it is no auth guard.
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
    # `else` block is listed under its negation, `!(condition)`.
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
          blocks << {"!(#{cond})", other.end(0)...other_end}
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
