require "../../engines/javascript_engine"
require "../../../miniparsers/egg_router_extractor"

module Analyzer::Javascript
  # Egg.js registers routes in `app/router.{js,ts}` (and the `app/router/**`
  # files it requires) against controllers loaded from `app/controller/**`,
  # addressed by their camelCased file path:
  #
  #   router.get('/users/:id', controller.admin.userInfo.show)
  #     → method `show` of app/controller/admin/user_info.js
  #
  # The controller method's body supplies the request params.
  class Egg < JavascriptEngine
    analyzer_for "js_egg"

    # `egg-bin` / `@eggjs/bin` is the dev runner; `"egg"` also matches the
    # package.json `"egg": { ... }` config block.
    PACKAGE_MARKERS = ["\"egg\":", "\"egg-core\":", "\"egg-bin\":", "\"@eggjs/bin\":"]
    ROUTER_FILE     = %r{/app/router(?:/.+)?\.[cm]?[jt]s$}
    CONTROLLER_DIR  = "/app/controller/"
    CONTROLLER_REF  = /\A(?:app\.|this\.)?controller\.([\w$.]+)\z/

    # egg-core's REST_MAP: action → verbs and path suffix. Only the actions
    # the controller defines are registered.
    RESOURCE_ACTIONS = {
      "index"   => {["GET"], ""},
      "new"     => {["GET"], "/new"},
      "create"  => {["POST"], ""},
      "show"    => {["GET"], "/:id"},
      "edit"    => {["GET"], "/:id/edit"},
      "update"  => {["PATCH", "PUT"], "/:id"},
      "destroy" => {["DELETE"], "/:id"},
    }

    record Handler, body : String, path : String, line : Int32

    @controller_code = {} of String => String
    @controller_lock = Mutex.new

    def analyze
      owners = js_package_owners(PACKAGE_MARKERS)
      return @result unless owners.values.includes?(true)

      routers = [] of String
      controllers = {} of Tuple(String, String) => String
      get_files_by_extensions(DEFAULT_EXTENSIONS).each do |path|
        relative = base_relative_path(path)
        if relative.matches?(ROUTER_FILE)
          routers << path if owned_by_js_package?(path, owners)
        elsif relative.includes?(CONTROLLER_DIR) && owned_by_js_package?(path, owners)
          expanded = Noir::PathScope.expand(path)
          idx = expanded.rindex(CONTROLLER_DIR) || next
          name = expanded[(idx + CONTROLLER_DIR.size)..].rchop(File.extname(expanded))
          # A `.ts` source and its compiled `.js` name the same controller.
          controllers[{expanded[0, idx + 4], camelize(name)}] ||= path
        end
      end

      include_callee = callees_needed?
      ordered_scan_files(routers) do |path|
        expanded = Noir::PathScope.expand(path)
        app_dir = expanded[0, (expanded.rindex("/app/router") || 0) + 4]
        Noir::EggRouterExtractor.extract(read_file_content(path)).flat_map do |route|
          endpoints_for(path, route, app_dir, controllers, include_callee)
        end
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    private def endpoints_for(path : String, route : Noir::EggRouterExtractor::Route, app_dir : String,
                              controllers : Hash(Tuple(String, String), String), include_callee : Bool) : Array(Endpoint)
      ref = Noir::EggRouterExtractor.string_literal(route.handler) || route.handler.match(CONTROLLER_REF).try(&.[1])

      if route.verb == "resources"
        file = ref.try { |name| controllers[{app_dir, name}]? }
        handlers = RESOURCE_ACTIONS.keys.to_h { |action| {action, file.try { |controller| method_handler(controller, action) }} }
        # No action found (inherited from a base controller, or a shape the
        # method regex misses): fall back to all of them.
        found = !handlers.values.all?(Nil)
        return RESOURCE_ACTIONS.flat_map do |action, (verbs, suffix)|
          handler = handlers[action]
          next [] of Endpoint if found && handler.nil?
          url = route.path.rchop('/') + suffix
          verbs.map { |verb| build(path, route.line, url, verb, handler, include_callee) }
        end
      end

      handler = if ref
                  controller, _, action = ref.rpartition('.')
                  controllers[{app_dir, controller}]?.try { |file| method_handler(file, action) }
                else
                  # An inline `async ctx => { ... }` handler.
                  Handler.new(route.handler, "", 0)
                end
      # koa-router registers `redirect` through `all`.
      verbs = route.verb.in?("all", "redirect") ? ANY_ROUTE_HTTP_METHODS : [Noir::JSRouteExtractor.normalize_http_method(route.verb)]
      verbs.map { |verb| build(path, route.line, route.path, verb, handler, include_callee) }
    end

    private def build(path : String, line : Int32, url : String, verb : String, handler : Handler?, include_callee : Bool) : Endpoint
      details = Details.new(PathInfo.new(path, line))
      details.add_path(PathInfo.new(handler.path, handler.line)) if handler && !handler.path.empty?
      endpoint = Endpoint.new(url, verb, details)
      return endpoint unless handler

      Noir::JSRouteExtractor.extract_query_params(handler.body, endpoint)
      Noir::JSRouteExtractor.extract_body_params(handler.body, endpoint)
      Noir::JSRouteExtractor.extract_header_params(handler.body, endpoint)
      Noir::JSRouteExtractor.extract_cookie_params(handler.body, endpoint)
      Noir::JSRouteExtractor.extract_path_params(handler.body, endpoint)
      if include_callee && !handler.path.empty?
        attach_js_callees(endpoint, Noir::JSCalleeExtractor.callees_for_function_body(handler.body, handler.path, handler.line, language: javascript_source_language(handler.path)))
      end
      endpoint
    end

    # Body of controller method `name`: a class method, an object-literal
    # method or an `exports.name = ...` function.
    # A TS return type may hold an object type (`Promise<{ list: T[] }>`);
    # one followed by `>`, `|`, `&`, `,` or `]` is not the body.
    private def method_handler(file : String, name : String) : Handler?
      content = controller_code(file)
      re = cached_regex("egg:#{name}") do
        /(?<![\w$.])(?:(?:public|private|protected|static|async|override)\s+)*(?:(?:module\.)?exports\.)?#{Regex.escape(name)}\s*(?:[:=]\s*(?:async\s+)?(?:function\b\s*\*?\s*)?)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::(?:[^{};=]|\{[^{}]*\}(?=\s*[>|&,\]]))+)?(?:=>\s*)?\{/
      end
      m = content.match(re) || return
      open = m.end(0) - 1
      close = Noir::JSRouteExtractor.find_matching_brace(content, open) || return
      Handler.new(content[(open + 1)...close], file, Noir::JSRouteExtractor.line_for_char_pos(content, m.begin(0)))
    end

    # Comment-stripped controller source, so a commented-out method is not
    # a definition. Memoized: every route and resource action re-reads it.
    private def controller_code(file : String) : String
      @controller_lock.synchronize do
        @controller_code[file] ||= Noir::JSRouteExtractor.strip_js_comments(read_file_content(file))
      end
    end

    # egg-core's loader key for a controller file path, `caseStyle: 'lower'`:
    # `admin/user_info` → `admin.userInfo`.
    private def camelize(name : String) : String
      name.split('/').join('.') do |segment|
        segment = segment.gsub(/[_-]([a-z])/i) { $1.upcase }
        segment.empty? ? segment : segment[0].downcase + segment[1..]
      end
    end
  end
end
