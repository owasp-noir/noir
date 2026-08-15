require "../../engines/php_engine"

module Analyzer::Php
  # Phalcon (https://phalcon.io/) is a PHP framework implemented as a C
  # extension. It exposes two independent routing styles that real apps mix
  # freely in the same codebase:
  #
  #   * Micro — a Slim-style DSL: `$app->get('/path', function () {...});`,
  #     optionally grouped with `Phalcon\Mvc\Micro\Collection`.
  #   * MVC — `Phalcon\Mvc\Router::add()` (+ `addGet`/`addPost`/…, optionally
  #     grouped with `Phalcon\Mvc\Router\Group`), PHPDoc annotation routing
  #     (`@RoutePrefix`/`@Get`/`@Route`) and convention-based
  #     controller/action dispatch (`ProductsController::showAction` ->
  #     `/products/show`).
  class Phalcon < PhpEngine
    analyzer_for "php_phalcon"

    HTTP_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]

    # ASCII byte values for the paren matcher below. Both are < 0x80, so
    # they can never collide with a UTF-8 multi-byte continuation/lead byte
    # (>= 0x80) — same invariant `PhpEngine#find_matching_php_close_brace`
    # relies on.
    private BYTE_LPAREN    = '('.ord.to_u8
    private BYTE_RPAREN    = ')'.ord.to_u8
    private BYTE_DQUOTE    = '"'.ord.to_u8
    private BYTE_SQUOTE    = '\''.ord.to_u8
    private BYTE_BACKSLASH = '\\'.ord.to_u8

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      include_callee = callees_needed?
      content = read_file_content(path)
      return endpoints unless phalcon_relevant?(content) || extends_phalcon_controller_base?(content)

      prefixes = extract_prefixes(content)

      endpoints.concat(analyze_verb_routes(content, prefixes, path, include_callee))
      endpoints.concat(analyze_map_routes(content, prefixes, path, include_callee))
      endpoints.concat(analyze_add_verb_routes(content, prefixes, path))
      endpoints.concat(analyze_generic_add_routes(content, prefixes, path))
      endpoints.concat(analyze_annotation_routes(path, content, include_callee))
      endpoints.concat(analyze_convention_routes(path, content, include_callee))

      dedup_endpoints(endpoints)
    end

    # Every PHP analyzer is fed every `.php` file in a project-wide scan, so
    # this gate is the only thing keeping Phalcon off other frameworks'
    # route/controller files. "Phalcon" itself is unambiguous — no other
    # ecosystem framework spells this namespace — so a plain substring match
    # is safe without the narrower `use X\Y;`-only matching Laminas needs
    # against the generic word "Zend".
    PHALCON_MARKER_RE = /Phalcon\\/

    private def phalcon_relevant?(content : String) : Bool
      content.matches?(PHALCON_MARKER_RE)
    end

    # Real Phalcon apps overwhelmingly route concrete controllers through a
    # shared local base — `phalcon/invo` and `phalcon/vokuro` (the
    # framework's own reference apps) both name it `ControllerBase` — rather
    # than extending `Phalcon\Mvc\Controller` directly. A concrete
    # `ProductsController extends ControllerBase` file has no reason to
    # mention `Phalcon\` itself, so the marker gate above would otherwise
    # miss the entire app.
    #
    # This resolves exactly one level of indirection: collect every class
    # name that *directly* extends `Phalcon\Mvc\Controller` project-wide
    # (memoized — computed once per scan, not per file), then admit a file
    # whose class extends one of those names even without its own `Phalcon\`
    # reference. A second-level base (a `ControllerBase` that itself extends
    # a *third* local class before reaching `Phalcon\Mvc\Controller`) is not
    # resolved — a deliberate, bounded trade-off against building a full
    # cross-file import graph for this one case.
    @phalcon_controller_base_names : Set(String)? = nil

    private def phalcon_controller_base_names : Set(String)
      cached = @phalcon_controller_base_names
      return cached if cached

      names = Set(String).new
      php_source_files.each do |file|
        file_content = read_file_content(file)
        # `Phalcon\Mvc\Controller` also matches a bare `use Phalcon\Mvc\
        # Controller;` import — the shape `ControllerBase` itself uses
        # (`class ControllerBase extends Controller`), not just a fully-
        # qualified `extends \Phalcon\Mvc\Controller`.
        next unless file_content.includes?("Phalcon\\Mvc\\Controller")

        file_content.scan(/class\s+(\w+)\s+extends\s+\\?([\w\\]+)\b/) do |m|
          names << m[1] if m[2].split('\\').last == "Controller"
        end
      end

      @phalcon_controller_base_names = names
      names
    end

    private def extends_phalcon_controller_base?(content : String) : Bool
      bases = phalcon_controller_base_names
      return false if bases.empty?

      content.scan(/class\s+\w+\s+extends\s+\\?([\w\\]+)\b/) do |m|
        return true if bases.includes?(m[1].split('\\').last)
      end
      false
    end

    # `$var->setPrefix('/prefix')` applies to both `Phalcon\Mvc\Micro\
    # Collection` (Micro route groups) and `Phalcon\Mvc\Router\Group` (MVC
    # router groups) — same call shape, different consumer. Track it once
    # per variable name rather than telling the two apart.
    private def extract_prefixes(content : String) : Hash(String, String)
      prefixes = {} of String => String
      content.scan(/\$(\w+)\s*->\s*setPrefix\s*\(\s*['"]([^'"\r\n]*)['"]\s*\)/i) do |m|
        prefixes[m[1]] ||= m[2]
      end
      prefixes
    end

    private def prefix_for(prefixes : Hash(String, String), receiver : String) : String
      prefixes[receiver]? || ""
    end

    # `->get(...)`/`->add(...)` are not unique to routing in a Phalcon app:
    # `Phalcon\Config`/`Phalcon\Di` objects answer to `->get($key, $default)`
    # (a 2-arg call shape identical to a route registration) and
    # `Phalcon\Validation` answers to `->add($field, $validator)`. Both are
    # extremely common in real Phalcon code — a `config->get('adapter',
    # 'Unknown')` or `validator->add('email', new Uniqueness(...))` call in a
    # model or service provider would otherwise read as a phantom route.
    # These are the receiver names real Phalcon apps conventionally use for
    # those non-routing services; a variable holding an actual Micro app,
    # Router or route Collection/Group is never named one of these.
    NON_ROUTE_RECEIVERS = Set{
      "config", "di", "container", "session", "cookies", "request",
      "response", "validator", "validation", "flash", "filter", "tag",
      "assets", "view", "dispatcher", "acl", "security", "crypt", "cache",
      "eventsmanager", "logger", "translate", "url", "escaper",
      "modelsmanager", "transactionmanager", "annotations",
    }

    private def route_receiver?(name : String) : Bool
      !NON_ROUTE_RECEIVERS.includes?(name.downcase)
    end

    # 1. Micro app / Collection direct verb calls:
    #    $app->get('/path', function () {...});
    #    $invoices->post('/add', 'add');
    VERB_REGEX = /\$(\w+)->(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"\r\n]+)['"]\s*,/i

    private def analyze_verb_routes(content : String, prefixes : Hash(String, String), path : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      pos = 0
      while m = content.match(VERB_REGEX, pos)
        after_args = m.end(0)
        receiver = m[1]
        handler_body, next_pos, body_start_line = extract_handler_body_with_end(content, after_args)

        if route_receiver?(receiver)
          method = m[2].upcase
          full_path = build_full_path(prefix_for(prefixes, receiver), normalize_phalcon_route_path(m[3]))

          params = extract_brace_path_params(full_path)
          params.concat(extract_handler_params(handler_body)) if handler_body
          params = dedup_params(params)

          endpoint = Endpoint.new(full_path, method, params, details.dup)
          attach_handler_callees(endpoint, handler_body, path, body_start_line) if include_callee && handler_body
          endpoints << endpoint
        end

        pos = next_pos
      end

      endpoints
    end

    # 2. map()/via(): $app->map('/repos/store/refs', 'actionProduct')->via(['GET', 'POST']);
    # Matched by call boundary (not a single-line path+comma regex) because
    # the trailing `->via(...)` lookup needs the position right after the
    # map() call's own closing paren — which a non-closure handler (a bare
    # string/callable-array, with no body to bound) doesn't otherwise give us.
    MAP_CALL_RE = /\$(\w+)->map\s*\(/i

    private def analyze_map_routes(content : String, prefixes : Hash(String, String), path : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      pos = 0
      while m = content.match(MAP_CALL_RE, pos)
        open_paren = m.end(0) - 1
        call_close = find_matching_close_paren(content, open_paren)

        if call_close
          args_str = content[(open_paren + 1)...call_close]
          path_match = args_str.match(/\A\s*['"]([^'"\r\n]+)['"]\s*,/)

          if path_match && route_receiver?(m[1])
            receiver = m[1]
            full_path = build_full_path(prefix_for(prefixes, receiver), normalize_phalcon_route_path(path_match[1]))

            handler_abs_pos = open_paren + 1 + path_match.end(0)
            handler_body, _, body_start_line = extract_handler_body_with_end(content, handler_abs_pos)

            methods = methods_from_via(content, call_close + 1)
            methods = ["GET"] if methods.empty?

            params = extract_brace_path_params(full_path)
            params.concat(extract_handler_params(handler_body)) if handler_body
            params = dedup_params(params)

            methods.each do |http_method|
              endpoint = Endpoint.new(full_path, http_method, params, details.dup)
              attach_handler_callees(endpoint, handler_body, path, body_start_line) if include_callee && handler_body
              endpoints << endpoint
            end
          end

          pos = call_close + 1
        else
          pos = m.end(0)
        end
      end

      endpoints
    end

    # 3. MVC Router explicit-verb helpers: $router->addGet('/path', 'Products::edit');
    ADD_VERB_REGEX = /\$(\w+)->add(Get|Post|Put|Patch|Delete|Options|Head)\s*\(\s*['"]([^'"\r\n]+)['"]/i

    private def analyze_add_verb_routes(content : String, prefixes : Hash(String, String), path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      content.scan(ADD_VERB_REGEX) do |m|
        receiver = m[1]
        next unless route_receiver?(receiver)

        method = m[2].upcase
        full_path = build_full_path(prefix_for(prefixes, receiver), normalize_phalcon_route_path(m[3]))
        params = extract_brace_path_params(full_path)
        endpoints << Endpoint.new(full_path, method, params, details.dup)
      end

      endpoints
    end

    # 4. MVC Router / Group generic add(), optionally chained with via():
    #    $router->add('/products/update', 'Products::update')->via(['POST', 'PUT']);
    #    $blog->add('/save', ['action' => 'save']);
    # Negative lookahead excludes addGet/addPost/... (case 3 above) and
    # addPurge (a real Phalcon Router method for the non-standard PURGE
    # verb, which this analyzer doesn't otherwise model — better to emit
    # nothing for it than to mis-report it as an unrestricted GET route).
    ADD_REGEX = /\$(\w+)->add(?!Get|Post|Put|Patch|Delete|Options|Head|Purge)\s*\(/i

    private def analyze_generic_add_routes(content : String, prefixes : Hash(String, String), path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      pos = 0
      while m = content.match(ADD_REGEX, pos)
        open_paren = m.end(0) - 1
        call_close = find_matching_close_paren(content, open_paren)

        if call_close
          args_str = content[(open_paren + 1)...call_close]
          path_match = args_str.match(/\A\s*['"]([^'"\r\n]+)['"]/)

          if path_match && route_receiver?(m[1])
            receiver = m[1]
            full_path = build_full_path(prefix_for(prefixes, receiver), normalize_phalcon_route_path(path_match[1]))

            # An unrestricted `add()` genuinely matches any HTTP verb at
            # runtime. Defaulting to GET here (rather than emitting all
            # seven methods) keeps output readable for the common case —
            # most unrestricted routes in real apps are simple content
            # pages — at the cost of under-reporting verb-agnostic routes
            # that also accept POST/PUT/etc. Documented as a known
            # limitation.
            methods = methods_from_via(content, call_close + 1)
            methods = ["GET"] if methods.empty?

            params = extract_brace_path_params(full_path)
            methods.each do |method|
              endpoints << Endpoint.new(full_path, method, params, details.dup)
            end
          end

          pos = call_close + 1
        else
          pos = m.end(0)
        end
      end

      endpoints
    end

    # Looks for an immediately-chained `->via(['GET', 'POST'])` right after
    # `after_call_pos` (the position right after a call's closing `)`).
    # Bounded lookahead keeps this a cheap, local check instead of a
    # full-file scan.
    private def methods_from_via(content : String, after_call_pos : Int32) : Array(String)
      return [] of String unless after_call_pos < content.size

      window_end = Math.min(content.size, after_call_pos + 40)
      lookahead = content[after_call_pos...window_end]
      via_match = lookahead.match(/\A\s*->via\s*\(/i)
      return [] of String unless via_match

      via_open = after_call_pos + via_match[0].size - 1
      via_close = find_matching_close_paren(content, via_open)
      return [] of String unless via_close

      extract_http_methods(content[(via_open + 1)...via_close])
    end

    private def extract_http_methods(text : String) : Array(String)
      methods = [] of String
      text.scan(/['"]?(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)['"]?/i) do |m|
        methods << m[1].upcase
      end
      methods.uniq
    end

    # 5. PHPDoc annotation routing:
    #      /**
    #       * @RoutePrefix('/api/products')
    #       */
    #      class ProductsController extends Controller {
    #          /** @Get('/search') */
    #          public function searchAction() {}
    #          /** @Route('/save', methods={'POST', 'PUT'}) */
    #          public function saveAction() {}
    #      }
    ANNOTATION_VERB_RE  = /@(Get|Post|Put|Patch|Delete|Options|Head)\s*\(\s*['"]([^'"]+)['"]/
    ANNOTATION_ROUTE_RE = /@Route\s*\(\s*['"]([^'"]+)['"]([^)]*)\)/m

    private struct PhalconClassScope
      getter path, body_start, body_end

      def initialize(@path : String, @body_start : Int32, @body_end : Int32)
      end
    end

    private def analyze_annotation_routes(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless content.includes?("@RoutePrefix") ||
                              content.includes?("@Route") ||
                              content.matches?(ANNOTATION_VERB_RE)

      details = Details.new(PathInfo.new(path))
      class_scopes = extract_class_route_prefixes(content)

      pos = 0
      while m = content.match(ANNOTATION_VERB_RE, pos)
        method = m[1].upcase
        route_path = m[2]
        after_annotation = m.end(0)

        method_body = extract_php_method_body_after(content, after_annotation)
        prefix = class_prefix_for_position(class_scopes, m.begin(0))
        full_path = build_full_path(prefix, normalize_phalcon_route_path(route_path))

        params = extract_brace_path_params(full_path)
        params.concat(extract_handler_params(method_body[0])) if method_body
        params = dedup_params(params)

        endpoint = Endpoint.new(full_path, method, params, details.dup)
        attach_method_callees(endpoint, method_body, path) if include_callee
        endpoints << endpoint

        pos = after_annotation
      end

      pos = 0
      while m = content.match(ANNOTATION_ROUTE_RE, pos)
        route_path = m[1]
        rest = m[2]
        after_annotation = m.end(0)

        methods = extract_http_methods(rest)
        methods = ["GET"] if methods.empty?

        method_body = extract_php_method_body_after(content, after_annotation)
        prefix = class_prefix_for_position(class_scopes, m.begin(0))
        full_path = build_full_path(prefix, normalize_phalcon_route_path(route_path))

        params = extract_brace_path_params(full_path)
        params.concat(extract_handler_params(method_body[0])) if method_body
        params = dedup_params(params)

        methods.each do |http_method|
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_method_callees(endpoint, method_body, path) if include_callee
          endpoints << endpoint
        end

        pos = after_annotation
      end

      endpoints
    end

    private def extract_class_route_prefixes(content : String) : Array(PhalconClassScope)
      scopes = [] of PhalconClassScope
      class_regex = /\bclass\s+\w+[^{]*\{/m
      offset = 0

      while class_match = content.match(class_regex, offset)
        class_start = class_match.begin(0)
        brace_pos = class_match.end(0) - 1
        class_end = find_matching_php_close_brace(content, brace_pos)
        if class_end
          prefix = route_prefix_before_class(content, class_start)
          scopes << PhalconClassScope.new(prefix, brace_pos + 1, class_end) if prefix
          offset = class_end + 1
        else
          offset = class_match.end(0)
        end
      end

      scopes
    end

    private def route_prefix_before_class(content : String, class_start : Int32) : String?
      lookbehind_start = Math.max(0, class_start - 600)
      preceding = content[lookbehind_start...class_start]
      m = preceding.match(/@RoutePrefix\s*\(\s*['"]([^'"]+)['"]/)
      m ? m[1] : nil
    end

    private def class_prefix_for_position(scopes : Array(PhalconClassScope), pos : Int32) : String
      scope = scopes.find { |s| pos >= s.body_start && pos < s.body_end }
      scope ? scope.path : ""
    end

    private def attach_method_callees(endpoint : Endpoint, method_body : Tuple(String, Int32)?, file_path : String)
      return unless method_body

      body, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    # 6. Convention-based controller/action dispatch: a public `fooAction`
    #    method on a controller extending `Phalcon\Mvc\Controller` maps to
    #    `/{controller}/{action}` (default action `index` is omitted), with
    #    any action parameters appended as positional path segments —
    #    `showAction($id)` on `ProductsController` -> `/products/show/{id}`.
    #
    #    Skipped entirely for controllers that already use PHPDoc annotation
    #    routing (case 5): an app wired with `RouterAnnotations` typically
    #    replaces the default convention router outright, so guessing
    #    convention routes alongside real annotation routes would invent
    #    endpoints that are never actually reachable.
    CONTROLLER_CLASS_RE = /class\s+(\w+)Controller\s+extends\s+\\?([\w\\]+)\b[^{]*\{/
    ACTION_METHOD_RE    = /public\s+function\s+(\w+)Action\s*\(([^)]*)\)/

    private def analyze_convention_routes(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints if content.includes?("@RoutePrefix") ||
                          content.includes?("@Route") ||
                          content.matches?(ANNOTATION_VERB_RE)

      class_match = content.match(CONTROLLER_CLASS_RE)
      return endpoints unless class_match

      # `extends \Phalcon\Mvc\Controller` (or a bare `extends Controller`
      # backed by a `use Phalcon\Mvc\Controller;` import) is the direct
      # case; anything else must resolve to a project-wide base collected
      # by `phalcon_controller_base_names` (see `extends_phalcon_controller_
      # base?` above) — the `ControllerBase` indirection real Phalcon apps
      # (phalcon/invo, phalcon/vokuro) actually use.
      parent_short = class_match[2].split('\\').last
      recognized_base = if parent_short == "Controller"
                          content.includes?("Phalcon\\Mvc\\Controller")
                        else
                          phalcon_controller_base_names.includes?(parent_short)
                        end
      return endpoints unless recognized_base

      controller_name = class_match[1].downcase
      details = Details.new(PathInfo.new(path))

      pos = 0
      while m = content.match(ACTION_METHOD_RE, pos)
        action_name = m[1].downcase
        params_sig = m[2]
        after_signature = m.end(0)
        pos = after_signature

        brace_pos = content.index('{', after_signature)
        next unless brace_pos

        body_end = find_matching_php_close_brace(content, brace_pos)
        method_body = body_end ? {content[(brace_pos + 1)...body_end], line_number_for_index(content, brace_pos)} : nil
        pos = body_end + 1 if body_end

        segments = [controller_name]
        segments << action_name unless action_name == "index"
        route_path = "/" + segments.join("/")
        route_path = "/" if controller_name == "index" && action_name == "index"

        positional_params = extract_positional_param_names(params_sig)
        route_path += positional_params.map { |name| "/{#{name}}" }.join unless route_path == "/"

        params = extract_brace_path_params(route_path)
        params.concat(extract_handler_params(method_body[0])) if method_body
        params = dedup_params(params)

        endpoint = Endpoint.new(route_path, "GET", params, details.dup)
        attach_method_callees(endpoint, method_body, path) if include_callee
        endpoints << endpoint
      end

      endpoints
    end

    private def extract_positional_param_names(params_sig : String) : Array(String)
      names = [] of String
      params_sig.scan(/\$(\w+)/) do |m|
        names << m[1]
      end
      names
    end

    private def normalize_phalcon_route_path(route : String) : String
      # `{id:[0-9]+}` -> `{id}`; legacy positional placeholders
      # `/:controller/:action/:params` -> `/{controller}/{action}/{params}`.
      normalized = route.gsub(/\{(\w+):[^}]+\}/) { |_| "{#{$~[1]}}" }
      normalized = normalized.gsub(/:([A-Za-z_]\w*)/) { |_| "{#{$~[1]}}" }
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = normalized.gsub(/\/+/, "/")
      normalized = normalized.chomp('/') if normalized.size > 1
      normalize_php_interpolation(normalized)
    end

    # Request/response accessors a Phalcon handler (Micro closure, MVC
    # controller action, or annotation-routed action) reads incoming data
    # through. `$this->request`/`$this->cookies` are available in every one
    # of those contexts — Phalcon binds Micro closures to the application
    # instance, so `$this` resolves the same way it does inside a
    # controller action.
    PARAM_PATTERNS = [
      {/->request->getQuery\s*\(\s*['"]([^'"]+)['"]/, "query"},
      {/->request->getPost\s*\(\s*['"]([^'"]+)['"]/, "form"},
      {/->request->getPut\s*\(\s*['"]([^'"]+)['"]/, "form"},
      {/->request->getPatch\s*\(\s*['"]([^'"]+)['"]/, "form"},
      {/->request->get\s*\(\s*['"]([^'"]+)['"]/, "query"},
      {/->request->getHeader\s*\(\s*['"]([^'"]+)['"]/, "header"},
      {/->cookies->get\s*\(\s*['"]([^'"]+)['"]/, "cookie"},
      {/->dispatcher->getParam\s*\(\s*['"]([^'"]+)['"]/, "path"},
    ]

    private def extract_handler_params(body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      PARAM_PATTERNS.each do |entry|
        pattern, type = entry
        body.scan(pattern) do |m|
          name = m[1]
          key = "#{type}\0#{name}"
          next if seen.includes?(key)

          params << Param.new(name, "", type)
          seen.add(key)
        end
      end

      params
    end

    private def attach_handler_callees(endpoint : Endpoint, body : String?, file_path : String, start_line : Int32?)
      return unless body && start_line

      callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    # Scans forward from `pos` for an immediate handler closure
    # (`function (...) {...}`). Returns the body text (or nil when the
    # handler is a string/callable-array reference, or brace matching
    # fails) together with the position after the handler so the caller
    # can resume scanning past it.
    private def extract_handler_body_with_end(content : String, pos : Int32) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      m = content[scan_pos..].match(closure_regex)
      return {nil, pos, nil} unless m

      brace_pos = scan_pos + m[0].size - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = line_number_for_index(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    # Byte-level scan for O(1) positional access instead of `String#[](Int)`,
    # which is O(n) on strings containing multi-byte characters — see
    # `PhpEngine#find_matching_php_close_brace` for the same fix applied to
    # brace matching. Comment-agnostic by design: call argument lists don't
    # carry inline `//`/`/* */` comments in practice, so unlike the brace
    # matcher this doesn't need to skip them, and nested `(`/`)` inside a
    # PHP `array(...)` literal balance correctly since every paren — code or
    # array — is counted the same way.
    private def find_matching_close_paren(content : String, open_pos : Int32) : Int32?
      bytes = content.to_slice
      start = content.char_index_to_byte_index(open_pos)
      return unless start && start < bytes.size && bytes[start] == BYTE_LPAREN

      depth = 0
      in_string = false
      quote = 0_u8
      escaped = false
      pos = start
      size = bytes.size

      while pos < size
        byte = bytes[pos]
        if in_string
          if escaped
            escaped = false
          elsif byte == BYTE_BACKSLASH
            escaped = true
          elsif byte == quote
            in_string = false
          end
        elsif byte == BYTE_DQUOTE || byte == BYTE_SQUOTE
          in_string = true
          quote = byte
        elsif byte == BYTE_LPAREN
          depth += 1
        elsif byte == BYTE_RPAREN
          depth -= 1
          return content.byte_index_to_char_index(pos) if depth == 0
        end
        pos += 1
      end

      nil
    end

    private def dedup_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
      seen = Set(String).new
      endpoints.select do |endpoint|
        key = "#{endpoint.method}\0#{endpoint.url}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end
  end
end
