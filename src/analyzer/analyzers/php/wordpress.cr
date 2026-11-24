require "../../engines/php_engine"
require "../../../utils/top_level_split"
require "../../../tagger/framework_taggers/php/php_access"

module Analyzer::Php
  # WordPress attack-surface extractor.
  #
  # WordPress does not expose a conventional route table; its
  # HTTP surface is registered imperatively through a handful of
  # well-known APIs:
  #
  #   * REST API   — `register_rest_route( $namespace, $route, $args )`
  #                  served under `/wp-json/{namespace}/{route}`.
  #   * Admin AJAX — `add_action( 'wp_ajax_{action}', ... )` and the
  #                  public `wp_ajax_nopriv_{action}` variant, dispatched
  #                  by `/wp-admin/admin-ajax.php?action={action}`.
  #   * Admin POST — `add_action( 'admin_post_{action}', ... )` /
  #                  `admin_post_nopriv_{action}`, dispatched by
  #                  `/wp-admin/admin-post.php?action={action}`.
  class Wordpress < PhpEngine
    analyzer_for "php_wordpress"

    ADMIN_AJAX_PATH = "/wp-admin/admin-ajax.php"
    ADMIN_POST_PATH = "/wp-admin/admin-post.php"

    # WordPress admin-ajax / admin-post dispatch on `$_REQUEST['action']`,
    # so both verbs are valid entry points.
    DISPATCH_METHODS = ["GET", "POST"]

    ALL_HTTP_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    TAGGER = "wordpress_analyzer"

    # `WP_REST_Server::` method-group constants → concrete HTTP verbs.
    REST_METHOD_CONSTANTS = {
      "READABLE"   => ["GET"],
      "CREATABLE"  => ["POST"],
      "EDITABLE"   => ["POST", "PUT", "PATCH"],
      "DELETABLE"  => ["DELETE"],
      "ALLMETHODS" => ["GET", "POST", "PUT", "PATCH", "DELETE"],
    }

    # add_action('wp_ajax_foo', ...) / wp_ajax_nopriv_foo
    # add_action('admin_post_foo', ...) / admin_post_nopriv_foo
    #
    # The trailing `\s*,` requires the hook name to be a *complete* string
    # literal (followed by the callback argument). This rejects a
    # prefix+variable concatenation like `'wp_ajax_myplugin_' . $tab`,
    # whose closing quote is followed by `.` — otherwise we would emit the
    # truncated phantom action `myplugin_`.
    HOOK_RE = /add_action\s*\(\s*['"](wp_ajax_(?:nopriv_)?|admin_post_(?:nopriv_)?)([A-Za-z0-9_\-]+)['"]\s*,/i

    # URLs some file of the scan registers a `nopriv_` hook for: the
    # dispatcher serves those to anyone, whichever file adds the hook.
    @public_hook_urls = Set(String).new

    def analyze
      scan_target_files.each do |path|
        next unless path.ends_with?(".php")
        content = read_file_content(path)
        next unless content.includes?("nopriv_")
        php_code(content).scan(HOOK_RE) do |m|
          @public_hook_urls << hook_url(m[1], m[2]) if m[1].downcase.ends_with?("nopriv_")
        end
      end
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      content = read_file_content(path)
      rest = content.includes?("register_rest_route")
      hooks = content.includes?("wp_ajax_") || content.includes?("admin_post_")
      return endpoints unless rest || hooks

      src = index_source(php_code(content))
      endpoints.concat(analyze_rest_routes(src, path)) if rest
      endpoints.concat(analyze_action_hooks(src, path)) if hooks

      endpoints
    end

    private record ClassScope, name : String, range : Range(Int32, Int32), strings : Hash(String, String)
    # `start` is the `function` keyword, `open`/`close` the body braces.
    private record FunctionDecl, name : String, params : String, start : Int32, open : Int32, close : Int32
    # One file's classes, functions and `define()` constants, indexed once so
    # per-route lookups do not rescan the file.
    private record Source, content : String, offsets : Noir::CharOffsets, lexer : Noir::PhpLexer,
      classes : Array(ClassScope), functions : Array(FunctionDecl), constants : Hash(String, String)

    FUNCTION_DECL_RE = /\bfunction\b\s*&?\s*(\w*)\s*\(([^{;]*?)\)[^{;]*\{/
    DEFINE_RE        = /\bdefine\s*\(\s*['"](\w+)['"]\s*,\s*(?:'([^'\\]*)'|"([^"\\$]*)")\s*\)/
    CONST_RE         = /\bconst\s+(?:\??[\w\\]+\s+)?(\w+)\s*=\s*(?:'([^'\\]*)'|"([^"\\$]*)")\s*;/

    private def index_source(content : String) : Source
      offsets = Noir::CharOffsets.new(content)
      lexer = Noir::PhpLexer.new(content)
      classes = class_scopes(content, lexer, offsets)
      functions = [] of FunctionDecl
      content.scan(FUNCTION_DECL_RE) do |m|
        start = offsets.begin(m)
        next unless lexer.in_code?(start)
        open = offsets.end(m) - 1
        close = lexer.matching_delimiter(open) || next
        functions << FunctionDecl.new(m[1], m[2], start, open, close)
      end
      constants = {} of String => String
      content.scan(DEFINE_RE) { |m| constants[m[1]] ||= m[2]? || m[3] }
      content.scan(CONST_RE) do |m|
        start = offsets.begin(m)
        constants[m[1]] ||= m[2]? || m[3] if classes.none?(&.range.includes?(start))
      end
      Source.new(content, offsets, lexer, classes, functions, constants)
    end

    # -- REST API --------------------------------------------------------

    private def analyze_rest_routes(src : Source, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = src.content
      offsets = src.offsets

      offset = 0
      while call_start = content.index("register_rest_route", offset)
        paren_open = content.index('(', call_start)
        paren_close = paren_open ? find_matching_paren(content, paren_open) : nil

        if paren_open && paren_close
          # Advance past the whole balanced call for the next iteration.
          offset = paren_close + 1
          args = content[(paren_open + 1)...paren_close]

          parts = split_top_level_args(args)
          klass = src.classes.find(&.range.includes?(call_start))
          # The namespace/route are the first two *positional* args, each a
          # string expression `resolve_string_expr` can evaluate.
          # Anything else can't be resolved statically — skip rather than emit
          # a bogus URL such as /wp-json/books/{id}/GET (which is what naively
          # scanning for the first two literals anywhere would produce).
          namespace = parts[0]?.try { |arg| resolve_string_expr(arg, src, klass, call_start) }
          route = parts[1]?.try { |arg| resolve_string_expr(arg, src, klass, call_start) }
          if namespace && route
            full_path = build_rest_path(namespace, route)
            path_params = Noir::URLPath.params(full_path, Noir::URLPath::BRACE_WORD, unique: true)
            details = Details.new(PathInfo.new(path, offsets.line(call_start)))

            rest_handlers(parts[2]? || "", src, klass).each do |method, (arg_names, typed, guard)|
              params = path_params.dup
              type = method == "GET" || method == "DELETE" ? "query" : "form"
              arg_names.each do |name|
                params << Param.new(name, "", type) unless params.any? { |param| param.name == name }
              end
              typed.each do |param|
                params << param unless params.any? { |known| known.name == param.name }
              end
              endpoint = Endpoint.new(full_path, method, params, details.dup)
              guard.try { |found| endpoint.add_tag(Tag.new(found.kind, "Protected by #{found.name}", TAGGER, requires: found.requires)) }
              endpoints << endpoint
            end
          end
        else
          # Malformed/unbalanced call — skip past this occurrence so the
          # scan makes progress instead of re-matching the same position.
          offset = call_start + "register_rest_route".size
        end
      end

      endpoints
    end

    # The tag name and guard name of a route's `permission_callback`, and
    # what it requires when that was read.
    record Guard, kind : String, name : String, requires : Array(Access::Clause)?

    # The verbs a route's third argument registers, each with the value
    # params its handler declares (`'args'`) or its callback reads, the header
    # and file params the callback reads, and the guard its
    # `permission_callback` imposes. That argument is one handler array or an
    # array of them, one per verb group.
    private def rest_handlers(handlers_arg : String, src : Source, klass : ClassScope?) : Hash(String, Tuple(Array(String), Array(Param), Guard?))
      handlers = [handlers_arg]
      if body = php_array_body(handlers_arg)
        elements = split_top_level_args(body).map(&.strip).reject(&.empty?)
        handlers = elements if !elements.empty? && elements.all? { |element| php_array_body(element) }
      end

      result = {} of String => Tuple(Array(String), Array(Param), Guard?)
      handlers.each do |handler|
        methods = extract_rest_methods(handler)
        methods = ["GET"] if methods.empty?
        names = rest_arg_names(handler)
        typed = [] of Param
        if (value = array_value(handler, CALLBACK_KEY_RE)) && (callback = callable_code(value, src, klass))
          code, request_var = callback
          code.scan(GET_PARAM_RE) { |m| names << m[1] }
          code.scan(/\$#{request_var}\s*\[\s*['"]([^'"]+)['"]\s*\]/) { |m| names << m[1] } if request_var
          code.scan(GET_HEADER_RE) { |m| typed << Param.new(m[1], "", "header") }
          code.scan(FILE_PARAMS_RE) { |m| typed << Param.new(m[1], "", "file") }
        end
        guard = permission_guard(handler, src, klass)
        methods.each do |method|
          # A verb two handler groups register is guarded only when both are.
          # `WP_REST_Server::match_request_to_handler` serves it with the
          # first, so that one's callback says what it requires.
          known = result[method]?
          merged = (first = known.try(&.[2])) && guard.try(&.copy_with(requires: first.requires))
          result[method] = known ? {known[0] + names, known[1] + typed, merged} : {names, typed, guard}
        end
      end
      result
    end

    CALLBACK_KEY_RE = /\A['"]callback['"]\s*=>\s*/
    GET_PARAM_RE    = /->\s*get_param\s*\(\s*['"]([^'"]+)['"]/
    GET_HEADER_RE   = /->\s*get_header\s*\(\s*['"]([^'"]+)['"]/
    FILE_PARAMS_RE  = /->\s*get_file_params\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]/
    FIRST_PARAM_RE  = /\A(?:static\s+)?(?:function|fn)\s*&?\s*\(\s*[^$)]*\$(\w+)/

    # The value of `'key' => value` in a handler array literal.
    private def array_value(handler : String, key_re : Regex) : String?
      body = php_array_body(handler) || return
      split_top_level_args(body).each do |element|
        element = element.strip
        if m = element.match(key_re)
          return element[m.end(0)..].strip
        end
      end
    end

    # The code a callable runs, with the name of its first parameter: a
    # closure's own text, or the body of the method of `klass` (else the free
    # function) it names. Nil for `__return_true` or a callable the file does
    # not show.
    private def callable_code(value : String, src : Source, klass : ClassScope?) : Tuple(String, String?)?
      if value.matches?(/\A(?:static\s+)?(?:function|fn)\b/)
        {value, value.match(FIRST_PARAM_RE).try(&.[1])}
      elsif name = (value.match(CALLABLE_ARRAY_RE) || value.match(CALLABLE_STRING_RE)).try(&.[1])
        return if name == "__return_true"
        decl = find_function(src, name, klass) || return
        {src.offsets.slice(decl.open + 1, decl.close), decl.params.match(/\$(\w+)/).try(&.[1])}
      end
    end

    PERMISSION_KEY_RE = /\A['"]permission_callback['"]\s*=>\s*/
    # `array( $this, 'check' )` / `[ __CLASS__, 'check' ]` / `'check'` /
    # `'Class::check'`: the name of the method or function called.
    CALLABLE_ARRAY_RE  = /\A(?:array\s*\(|\[)\s*[^,]+,\s*['"](\w+)['"]\s*(?:\)|\])\z/i
    CALLABLE_STRING_RE = /\A['"](?:[\w\\]+::)?(\w+)['"]\z/
    CAPABILITY_FNS     = "current_user_can|user_can|current_user_can_for_site|current_user_can_for_blog"
    LOGIN_FNS          = "is_user_logged_in"
    # A check that decides the callback: its return value
    # (`return current_user_can('x');`), or the whole condition of an `if`
    # that refuses (`if ( ! current_user_can('x') ) { return new WP_Error(...); }`).
    # A check under a further condition (`'edit' === $context && ! ...`)
    # leaves the default path open, so it is not one.
    CAPABILITY_CHECK_RE = /(?:\breturn\s+(?:\(\s*bool\s*\)\s*)?|\bif\s*\(\s*!\s*)(?:#{CAPABILITY_FNS})\s*\((?:[^,()]*,)?\s*(?:['"]([\w-]+)['"])?(?:[^()]|\([^()]*\))*\)\s*(?:;|\)\s*(?:\{\s*)?(?:return|throw)\b)/
    LOGIN_CHECK_RE      = /(?:\breturn\s+(?:\(\s*bool\s*\)\s*)?|\bif\s*\(\s*!\s*)(?:#{LOGIN_FNS})\s*\(\s*\)\s*(?:;|\)\s*(?:\{\s*)?(?:return|throw)\b)/

    # The guard a handler's `permission_callback` imposes: a capability check
    # (`current_user_can('edit_posts')`) is authorization, a logged-in check
    # authentication. The callback is a closure, a method of the route's
    # class, or a function of the file outside any class. `__return_true`,
    # a callback the file does not show, or one that checks neither
    # decisively, is no guard.
    private def permission_guard(handler : String, src : Source, klass : ClassScope?) : Guard?
      value = array_value(handler, PERMISSION_KEY_RE) || return
      code = callable_code(value, src, klass).try(&.[0]) || return
      requires = PhpAccess.wordpress_permission(code).try { |cnf| Access.clauses(cnf, value) }
      if m = code.match(CAPABILITY_CHECK_RE)
        Guard.new("authz", "WordPress permission_callback #{m[1]? ? "current_user_can('#{m[1]}')" : "capability check"}", requires)
      elsif code.matches?(LOGIN_CHECK_RE)
        Guard.new("auth", "WordPress permission_callback login check", requires)
      end
    end

    # `function name(...) { ... }`: inside `klass` (a method of the route's
    # class), else a free function, outside every class.
    private def find_function(src : Source, name : String, klass : ClassScope?) : FunctionDecl?
      found = src.functions.find do |decl|
        decl.name == name && (klass ? klass.range.includes?(decl.start) : src.classes.none?(&.range.includes?(decl.start)))
      end
      # A plain function the route's class names as a string callback.
      found || (klass && find_function(src, name, nil))
    end

    REST_ARGS_KEY_RE = /\A['"]args['"]\s*=>\s*/
    ARRAY_KEY_RE     = /\A['"]([^'"]+)['"]\s*=>/

    # Keys of a handler's `'args' => array( 'per_page' => …, … )`.
    private def rest_arg_names(handler : String) : Array(String)
      body = php_array_body(handler)
      return [] of String unless body
      split_top_level_args(body).each do |element|
        element = element.strip
        next unless key = element.match(REST_ARGS_KEY_RE)
        args_body = php_array_body(element[key.end(0)..])
        return [] of String unless args_body
        return split_top_level_args(args_body).compact_map(&.strip.match(ARRAY_KEY_RE).try(&.[1]))
      end
      [] of String
    end

    # Inside of an `array( … )` / `[ … ]` literal, or nil for anything else.
    private def php_array_body(expr : String) : String?
      s = expr.strip
      if m = s.match(/\Aarray\s*\((.*)\)\z/mi)
        m[1]
      elsif s.starts_with?('[') && s.ends_with?(']')
        s[1...-1]
      end
    end

    STRING_PROPERTY_RE = /\b(?:public|protected|private|var)\s+(?:static\s+)?(?:\??[\w\\]+\s+)?\$(\w+)\s*=\s*(?:'([^'\\]*)'|"([^"\\$]*)")/
    # `$this->namespace = 'wp/v2';`, as a constructor sets it.
    THIS_ASSIGN_RE = /\$this\s*->\s*(\w+)\s*=\s*(?:'([^'\\]*)'|"([^"\\$]*)")\s*;/
    CLASS_DECL_RE  = /(?<![:\w$>])(?<!new\s)\bclass\s+(\w+)(?:\s+extends\s+\\?(?:[\w\\]+\\)?(\w+))?[^{;]*\{/

    # `{body range, string properties}` of each class in the file, for
    # resolving `$this->namespace` against the class the call sits in. A
    # property is declared (`protected $namespace = 'myplugin/v2';`) or
    # assigned in a method (`$this->namespace = 'wp/v2';`, which wins), in
    # the class or a parent class of the same file. One inherited from a
    # class in another file, or a trait, is not seen. Class constants are
    # kept under `::NAME`, which no property name can collide with.
    private def class_scopes(content : String, lexer : Noir::PhpLexer, offsets : Noir::CharOffsets) : Array(ClassScope)
      found = [] of Tuple(String, String?, Range(Int32, Int32), Hash(String, String))
      content.scan(CLASS_DECL_RE) do |m|
        next unless lexer.in_code?(offsets.begin(m))
        open = offsets.end(m) - 1
        close = lexer.matching_delimiter(open) || next
        body = offsets.slice(open, close)
        properties = {} of String => String
        assigned = {} of String => String
        body.scan(STRING_PROPERTY_RE) { |prop| properties[prop[1]] ||= prop[2]? || prop[3] }
        body.scan(THIS_ASSIGN_RE) { |prop| assigned[prop[1]] ||= prop[2]? || prop[3] }
        body.scan(CONST_RE) { |prop| properties["::#{prop[1]}"] ||= prop[2]? || prop[3] }
        found << {m[1], m[2]?, open..close, properties.merge(assigned)}
      end
      by_name = found.to_h { |(name, parent, _, props)| {name, {parent, props}} }
      found.map do |(name, parent, range, props)|
        seen = Set(String).new
        while parent && seen.add?(parent) && (inherited = by_name[parent]?)
          props = inherited[1].merge(props)
          parent = inherited[0]
        end
        ClassScope.new(name, range, props)
      end
    end

    CLASS_CONST_REF_RE = /\A\\?([\w\\]+)::(\w+)\z/
    INTERPOLATION_RE   = /(?<!\\)(?:\{\$this->(\w+)\}|\$this->(\w+)|\{\$(\w+)\}|\$\{(\w+)\}|\$(\w+))/
    # Hops through `$a = $b . 'x';` assignments before giving up.
    MAX_VAR_HOPS = 3

    # The value of a `.` concatenation of string literals (a double-quoted
    # one interpolated), `$this->prop`, class constants, `define()`/`const`
    # constants of the file, and local variables assigned once in the
    # function around `pos`; nil when any piece is something else.
    private def resolve_string_expr(arg : String, src : Source, klass : ClassScope?, pos : Int32, hops : Int32 = 0) : String?
      String.build do |io|
        Noir::TopLevelSplit.split(arg, '.', SPLIT_ARGS_RULES).each do |piece|
          io << (resolve_string_piece(piece.strip, src, klass, pos, hops) || return)
        end
      end
    end

    private def resolve_string_piece(piece : String, src : Source, klass : ClassScope?, pos : Int32, hops : Int32) : String?
      if m = piece.match(/\A'((?:[^'\\]|\\.)*)'\z/)
        m[1]
      elsif m = piece.match(/\A"((?:[^"\\]|\\.)*)"\z/)
        interpolate(m[1], src, klass, pos, hops)
      elsif m = piece.match(/\A\$this->(\w+)\z/)
        klass.try(&.strings[m[1]]?)
      elsif m = piece.match(/\A\$(\w+)\z/)
        local_string(m[1], src, klass, pos, hops)
      elsif m = piece.match(CLASS_CONST_REF_RE)
        owner = m[1] == "self" || m[1] == "static" ? klass : src.classes.find(&.name.==(m[1].split('\\').last))
        owner.try(&.strings["::#{m[2]}"]?)
      elsif piece.matches?(/\A[A-Za-z_]\w*\z/)
        src.constants[piece]?
      end
    end

    # A double-quoted string's `{$this->prop}` / `$this->prop` / `{$var}` /
    # `${var}` / `$var` pieces expanded; nil when one is unknown.
    private def interpolate(text : String, src : Source, klass : ClassScope?, pos : Int32, hops : Int32) : String?
      return text unless text.includes?('$')
      String.build do |io|
        last = 0
        text.scan(INTERPOLATION_RE) do |m|
          io << text[last...m.begin(0)]
          value = if prop = m[1]? || m[2]?
                    klass.try(&.strings[prop]?)
                  else
                    local_string(m[3]? || m[4]? || m[5], src, klass, pos, hops)
                  end
          io << (value || return)
          last = m.end(0)
        end
        io << text[last..]
      end
    end

    # The string value of `$name` when the function around `pos` (the file,
    # outside any function) assigns it exactly once; any second or compound
    # assignment leaves it unresolved.
    private def local_string(name : String, src : Source, klass : ClassScope?, pos : Int32, hops : Int32) : String?
      return if hops >= MAX_VAR_HOPS
      scope = src.functions.select { |decl| decl.open < pos && pos < decl.close }.max_by?(&.open)
      body = scope ? src.offsets.slice(scope.open + 1, scope.close) : src.content
      value = nil
      body.scan(/(?<![\w$])\$#{name}\s*([.+\-*\/?]*)=(?![=>])\s*([^;]*);/) do |m|
        return if value || !m[1].empty?
        value = m[2]
      end
      value.try { |expr| resolve_string_expr(expr, src, klass, pos, hops + 1) }
    end

    # `/wp-json/` + namespace + route, collapsing duplicate slashes.
    private def build_rest_path(namespace : String, route : String) : String
      ns = namespace.strip.strip('/')
      rt = route.strip
      combined = "/wp-json/#{ns}/#{rt}"
      combined = combined.gsub(/\/+/, "/")
      combined = combined.chomp('/') if combined.size > 1
      normalize_wp_route(combined)
    end

    # Collect every HTTP verb referenced inside the `register_rest_route`
    # argument list: literal `'methods' => 'GET'` / `array('GET','POST')`
    # forms plus the `WP_REST_Server::READABLE`-style constants.
    private def extract_rest_methods(raw_args : String) : Array(String)
      methods = [] of String
      # Strip PHP comments so a commented-out `'methods' => 'DELETE'` (or a
      # `WP_REST_Server::EDITABLE` in a docblock) does not emit a phantom verb.
      args = strip_php_comments(raw_args)

      REST_METHOD_CONSTANTS.each do |constant, verbs|
        methods.concat(verbs) if args.includes?("WP_REST_Server::#{constant}")
      end

      # `'methods' => 'GET, POST'` / `"methods" => "GET"`.
      args.scan(/['"]methods['"]\s*=>\s*['"]([^'"]+)['"]/i) do |m|
        m[1].split(',').each do |verb|
          v = verb.strip.upcase
          methods << v if ALL_HTTP_VERBS.includes?(v)
        end
      end

      # `'methods' => array('GET','POST')` / `['GET','POST']`.
      args.scan(/['"]methods['"]\s*=>\s*(?:array\s*\(|\[)([^\)\]]*)/i) do |m|
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |verb|
          v = verb[1].strip.upcase
          methods << v if ALL_HTTP_VERBS.includes?(v)
        end
      end

      methods.uniq
    end

    # -- Admin AJAX / admin-post ----------------------------------------

    private def analyze_action_hooks(src : Source, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      seen = Set(String).new
      offsets = src.offsets

      # The dispatcher runs `wp_ajax_<action>` / `admin_post_<action>` for a
      # logged-in user only; the `nopriv_` hook is what serves anyone else.
      src.content.scan(HOOK_RE) do |match|
        action = match[2]
        next if action.empty?

        url = hook_url(match[1], action)
        call_start = offsets.begin(match)
        details = Details.new(PathInfo.new(path, offsets.line(call_start)))
        code = hook_callback_code(src, call_start)

        DISPATCH_METHODS.each do |method|
          dedup_key = "#{method} #{url}"
          next if seen.includes?(dedup_key)
          seen.add(dedup_key)

          params = [Param.new("action", action, "query")]
          if code
            hook_params(code, method).each do |param|
              params << param unless params.any? { |known| known.name == param.name }
            end
          end
          endpoint = Endpoint.new(url, method, params, details.dup)
          unless @public_hook_urls.includes?(url)
            # admin-ajax.php / admin-post.php run this hook only for a logged-in user.
            logged_in = Access::Clause.new([Access::Atom.new(:authenticated)], "#{match[1].downcase}#{action}")
            endpoint.add_tag(Tag.new("auth", "Protected by WordPress #{match[1].downcase} hook (logged-in users only)", TAGGER, requires: [logged_in]))
          end
          endpoints << endpoint
        end
      end

      endpoints
    end

    NONCE_ARG_RE = /\bcheck_(?:ajax|admin)_referer\s*\(\s*['"][^'"]*['"]\s*,\s*['"]([^'"]+)['"]/

    # The code of the callback (second argument) of the `add_action(` call
    # at `call_start`.
    private def hook_callback_code(src : Source, call_start : Int32) : String?
      open = src.offsets.index('(', call_start) || return
      close = src.lexer.matching_delimiter(open) || return
      value = split_top_level_args(src.offsets.slice(open + 1, close))[1]?.try(&.strip) || return
      callable_code(value, src, src.classes.find(&.range.includes?(call_start))).try(&.[0])
    end

    # Request input a hook callback reads. The dispatcher takes GET and POST
    # alike, so `$_REQUEST` follows the endpoint's verb.
    private def hook_params(code : String, method : String) : Array(Param)
      params = [] of Param
      each_superglobal_read(code) do |source, name|
        type = case source
               when "GET"     then "query"
               when "POST"    then "form"
               when "REQUEST" then method == "GET" ? "query" : "form"
               when "COOKIE"  then "cookie"
               when "FILES"   then "file"
               else
                 next unless name.starts_with?("HTTP_")
                 name = name.lchop("HTTP_").tr("_", "-")
                 "header"
               end
        params << Param.new(name, "", type)
      end
      code.scan(NONCE_ARG_RE) { |m| params << Param.new(m[1], "", method == "GET" ? "query" : "form") }
      params
    end

    private def hook_url(hook_prefix : String, action : String) : String
      base_path = hook_prefix.downcase.starts_with?("wp_ajax_") ? ADMIN_AJAX_PATH : ADMIN_POST_PATH
      "#{base_path}?action=#{action}"
    end

    # -- Helpers ---------------------------------------------------------

    # WordPress REST routes are PCRE fragments. Rewrite named capture
    # groups to `{name}` and strip the residual regex syntax that would
    # otherwise leak into the emitted URL:
    #   /books/(?P<id>\d+)          -> /books/{id}
    #   /(?P<type>(post|page))      -> /{type}       (balanced inner group)
    #   /thing(?:/(?P<id>\d+))?     -> /thing/{id}   (non-capturing + optional)
    private def normalize_wp_route(route : String) : String
      result = replace_named_groups(route)
      strip_wp_regex_artifacts(result)
    end

    # Replace `(?P<name>...)` / `(?<name>...)` with `{name}`, consuming the
    # *balanced* group body (which may itself contain nested `(...)`), so an
    # inner group does not truncate the match and leave a stray `)`.
    private def replace_named_groups(route : String) : String
      result = route
      loop do
        m = result.match(/\(\?P?<([A-Za-z_]\w*)>/)
        break unless m
        open_paren = m.begin(0)
        break unless open_paren
        close = matching_regex_paren(result, open_paren)
        break unless close
        result = result[0...open_paren] + "{#{m[1]}}" + result[(close + 1)..]
      end
      result
    end

    # Drop leftover PCRE syntax that is never part of a real URL path:
    # non-capturing groups, bare grouping parens, anchors, and quantifiers.
    # `{name}` placeholders are untouched (they contain none of these).
    private def strip_wp_regex_artifacts(route : String) : String
      r = route.gsub("(?:", "")
      r = r.gsub(/[()^$?]/, "")
      r = r.gsub(/\/+/, "/")
      r = r.chomp('/') if r.size > 1
      r
    end

    # Balance-match the `)` closing the `(` at `open`, honoring `\`-escapes
    # and `[...]` character classes (a `)` inside a class or after a
    # backslash is literal, not a group close). Scoped to regex fragments —
    # unlike find_matching_paren it does not treat `#`/`//` as comments.
    private def matching_regex_paren(s : String, open : Int32) : Int32?
      depth = 0
      in_class = false
      i = open
      while i < s.size
        c = s[i]
        if c == '\\'
          i += 2
          next
        elsif in_class
          in_class = false if c == ']'
        elsif c == '['
          in_class = true
        elsif c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end

    # Remove `//`, `#`, and `/* */` PHP comments, preserving string
    # literals (so a `#` or `//` inside a quoted route is kept).
    private def strip_php_comments(code : String) : String
      out = String::Builder.new
      i = 0
      size = code.size
      in_string = false
      quote = '\0'
      escaped = false
      while i < size
        c = code[i]
        nxt = i + 1 < size ? code[i + 1] : '\0'
        if in_string
          out << c
          if escaped
            escaped = false
          elsif c == '\\'
            escaped = true
          elsif c == quote
            in_string = false
          end
          i += 1
        elsif c == '\'' || c == '"'
          in_string = true
          quote = c
          out << c
          i += 1
        elsif c == '/' && nxt == '/'
          i += 2
          while i < size && code[i] != '\n'
            i += 1
          end
        elsif c == '#'
          i += 1
          while i < size && code[i] != '\n'
            i += 1
          end
        elsif c == '/' && nxt == '*'
          i += 2
          while i < size && !(code[i] == '*' && (i + 1 < size ? code[i + 1] : '\0') == '/')
            i += 1
          end
          i += 2
        else
          out << c
          i += 1
        end
      end
      out.to_s
    end

    # `Rules::SHARED_DEPTH_RAW` with a trailing empty dropped and, like
    # erlang/cowboy.cr, WITHOUT clamping: the body this replaces closed
    # brackets with a bare `depth -= 1`, so a fragment beginning with a
    # closer (`")x, y"`) drives depth negative and stops splitting. That is
    # observable on the regex-sliced input this actually receives, so it is
    # preserved rather than normalised.
    #
    # File-local because wordpress is the only splitter pairing
    # `clamp: false` with unstripped parts.
    SPLIT_ARGS_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace,
      quotes: "\"'",
      escape: Noir::TopLevelSplit::Escape::InQuotes,
      strip: false,
      empties: Noir::TopLevelSplit::Empties::DropTrailing,
      per_kind: false,
      clamp: false,
    )

    # Split a PHP argument list on top-level commas, ignoring commas
    # nested inside (), [], {} or quoted strings. Only the first two
    # arguments are needed, but splitting fully keeps the logic simple.
    #
    # The empty-input guard is the old tail condition
    # `if start <= args.size - 1 || parts.empty?`, whose `|| parts.empty?`
    # arm fires for exactly one input: `""`, which yielded `[""]` and not
    # `[]`. `Empties::DropTrailing` can only return `[]` for that same
    # input, so restoring it here is exact — and cheaper than a fourth
    # `Empties` case for one caller.
    private def split_top_level_args(args : String) : Array(String)
      parts = Noir::TopLevelSplit.split(args, ',', SPLIT_ARGS_RULES)
      parts.empty? ? [""] : parts
    end

    # ASCII delimiters for the paren matcher below (mirrors PhpEngine's
    # brace matcher; all < 0x80 so UTF-8 multi-byte sequences are safe).
    private BYTE_NL     = '\n'.ord.to_u8
    private BYTE_STAR   = '*'.ord.to_u8
    private BYTE_SLASH  = '/'.ord.to_u8
    private BYTE_HASH   = '#'.ord.to_u8
    private BYTE_BSLASH = '\\'.ord.to_u8
    private BYTE_DQ     = '"'.ord.to_u8
    private BYTE_SQ     = '\''.ord.to_u8
    private BYTE_OPAREN = '('.ord.to_u8
    private BYTE_CPAREN = ')'.ord.to_u8

    # Find the `)` that closes the `(` at `open_pos`, skipping parens
    # inside strings and comments. Byte-scanned to stay linear on
    # multi-byte (e.g. CJK-commented) source.
    private def find_matching_paren(content : String, open_pos : Int32) : Int32?
      bytes = content.to_slice
      start = content.char_index_to_byte_index(open_pos)
      return unless start && start < bytes.size && bytes[start] == BYTE_OPAREN

      depth = 0
      in_string = false
      in_line_comment = false
      in_block_comment = false
      escaped = false
      quote = 0_u8
      pos = start
      size = bytes.size

      while pos < size
        char = bytes[pos]
        next_char = pos + 1 < size ? bytes[pos + 1] : 0_u8

        if in_line_comment
          in_line_comment = false if char == BYTE_NL
        elsif in_block_comment
          if char == BYTE_STAR && next_char == BYTE_SLASH
            in_block_comment = false
            pos += 1
          end
        elsif in_string
          if escaped
            escaped = false
          elsif char == BYTE_BSLASH
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == BYTE_SLASH && next_char == BYTE_SLASH
          in_line_comment = true
          pos += 1
        elsif char == BYTE_SLASH && next_char == BYTE_STAR
          in_block_comment = true
          pos += 1
        elsif char == BYTE_HASH
          in_line_comment = true
        elsif char == BYTE_DQ || char == BYTE_SQ
          in_string = true
          quote = char
        elsif char == BYTE_OPAREN
          depth += 1
        elsif char == BYTE_CPAREN
          depth -= 1
          return content.byte_index_to_char_index(pos) if depth == 0
        end

        pos += 1
      end

      nil
    end
  end
end
