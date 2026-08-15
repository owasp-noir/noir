require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  # Sails.js routes come from two sources:
  #
  #   1. Explicit routes hand-written in `config/routes.js` -- an object
  #      literal mapping `'METHOD /path'` address strings to targets
  #      (controller/action strings, `{controller, action}` objects,
  #      inline handler functions, view/redirect targets, ...).
  #   2. Blueprint routes Sails auto-generates per controller/model unless
  #      disabled, plus the "actions2" convention of one file per action
  #      under `api/controllers/<subdir>/<action>.js`, whose URL is the
  #      action's path relative to `api/controllers` (no extension).
  #
  # Both are gated on `discover_sails_roots`, which requires a
  # `config/routes.js` file AND a `package.json` declaring the `sails`
  # dependency in the SAME directory -- not either alone. Node projects are
  # noir's most crowded language (Express/Koa/Nest/Fastify/Hapi/Restify all
  # coexist), and blueprint inference in particular works off file
  # *presence* rather than an explicit registration call, so it is
  # especially prone to stealing routes from a neighboring framework's
  # `api/controllers/*.js`-shaped tree in the same repo (the exact class of
  # bug the #2417-2432 project-scoping campaign fixed for other analyzers).
  class Sails < JavascriptEngine
    analyzer_for "js_sails"

    ROUTES_FILE_SUFFIX = "/config/routes.js"
    PACKAGE_MARKER     = /"sails"\s*:\s*"/

    JS_SOURCE_EXTENSIONS = [".js", ".ts", ".mjs", ".cjs"]

    HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    # Address verbs recognised in `config/routes.js` route keys. `ALL`
    # matches any method (expanded below); QUERY is accepted for parity
    # with the rest of noir's JS analyzers even though Sails' own docs
    # don't mention it explicitly -- an app that wires one up by hand
    # still deserves to be reported.
    ADDRESS_METHOD_RE = /\A(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|QUERY|ALL)[ \t]+(\/.*)\z/i

    # One quoted-key route entry per line is the universal `routes.js`
    # style (every official example and every real app follows it). The
    # captured group requires the string to actually look like a route
    # address -- an optional method name followed by `/...` -- so nested
    # option keys inside a target object (`locals: {...}`, `cors: {...}`)
    # can't be mistaken for a sibling route entry: those keys are bare
    # identifiers, never quoted strings immediately followed by `:`.
    ADDRESS_LINE_RE = /^[ \t]*['"]((?:[A-Za-z]+[ \t]+)?\/[^'"]*)['"][ \t]*:/m

    CONTROLLER_FILE_RE = /\A([A-Za-z0-9_]+)Controller\.(js|ts|mjs|cjs)\z/

    MODEL_FILE_RE = /\A([A-Za-z0-9_]+)\.(js|ts|mjs|cjs)\z/

    # {method, sub-path} pairs generated for every blueprint-eligible
    # controller/model identity, mirroring Sails' current (>=1.0) default
    # REST blueprint bindings: find/create/findOne/update/destroy.
    # Association routes (populate/add/remove/replace) and the dev-only
    # shortcut GET routes are intentionally not modeled -- see the PR
    # description for the reasoning.
    BLUEPRINT_ROUTES = [
      {"GET", ""},
      {"POST", ""},
      {"GET", "/:id"},
      {"PATCH", "/:id"},
      {"DELETE", "/:id"},
    ]

    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)

      discover_sails_roots.each do |root, routes_file|
        analyze_routes_file(routes_file, result)
        analyze_blueprints(root, result)
        static_dirs << {"static_path" => "/", "file_path" => "#{root}/assets"}
      end

      process_js_static_dirs(static_dirs, result)
      result
    end

    # A Sails app root is a directory that both owns a `config/routes.js`
    # file AND has a `package.json` declaring a dependency on the `sails`
    # package. See the class comment for why both signals are required.
    private def discover_sails_roots : Array(Tuple(String, String))
      roots = [] of Tuple(String, String)

      get_files_by_basename("routes.js").each do |file|
        next unless file.ends_with?(ROUTES_FILE_SUFFIX)
        root = file[0, file.size - ROUTES_FILE_SUFFIX.size]
        next if root.empty?
        next unless sails_package_present?(root)
        roots << {root, file}
      end

      roots
    end

    private def sails_package_present?(root : String) : Bool
      get_files_by_basename("package.json").any? do |file|
        next false unless File.dirname(file) == root
        begin
          content_matches?(read_file_content(file), PACKAGE_MARKER)
        rescue IO::Error
          false
        end
      end
    end

    # ---------------------------------------------------------------------
    # Explicit `config/routes.js` routes
    # ---------------------------------------------------------------------

    private def analyze_routes_file(routes_file : String, result : Array(Endpoint))
      raw_content = read_file_content(routes_file)
      content = Noir::JSRouteExtractor.strip_js_comments(raw_content)

      content.scan(ADDRESS_LINE_RE) do |m|
        next unless m.size >= 2
        match_start = m.begin(0)
        match_end = m.end(0)
        next unless match_start && match_end

        methods, url = parse_sails_address(m[1].strip)
        next if methods.empty? || url.empty?

        line = content[0...match_start].count('\n') + 1
        value_start = skip_ws(content, match_end)

        methods.each do |method|
          details = Details.new(PathInfo.new(routes_file, line))
          endpoint = Endpoint.new(url, method, details)
          url.scan(/:(\w+)/) do |pm|
            endpoint.push_param(Param.new(pm[1], "", "path")) if pm.size > 0
          end
          apply_inline_handler_params(content, value_start, endpoint)
          result << endpoint
        end
      end
    end

    # Splits a route address like `"GET /users/:id"` or `"/alias"` into its
    # HTTP method(s) and URL path. Regex addresses (`r|...|...`) never
    # reach here -- `ADDRESS_LINE_RE` requires the string to start with a
    # verb+space or a bare `/`.
    private def parse_sails_address(addr : String) : Tuple(Array(String), String)
      if md = addr.match(ADDRESS_METHOD_RE)
        method = md[1].upcase
        path = md[2].strip
        methods = method == "ALL" ? HTTP_METHODS : [method]
        {methods, path}
      elsif addr.starts_with?("/")
        {HTTP_METHODS, addr}
      else
        {[] of String, ""}
      end
    end

    # Best-effort param extraction for inline function targets and object
    # targets (`{ controller: ..., action: ... }`, `{ fn: function(req,
    # res) {...} }`). String/redirect/view targets and policy-chain arrays
    # carry no handler body to inspect and are left with address-derived
    # params only.
    private def apply_inline_handler_params(content : String, value_start : Int32, endpoint : Endpoint)
      return if value_start >= content.size
      ch = content[value_start]?
      return unless ch

      body =
        if ch == '{'
          close = Noir::JSRouteExtractor.find_matching_brace(content, value_start)
          close ? content[value_start..close] : nil
        else
          function_target_body(content, value_start)
        end
      return unless body

      Noir::JSRouteExtractor.extract_query_params(body, endpoint)
      Noir::JSRouteExtractor.extract_body_params(body, endpoint)
      Noir::JSRouteExtractor.extract_header_params(body, endpoint)
      Noir::JSRouteExtractor.extract_cookie_params(body, endpoint)
    end

    # Recognises `function(req, res) {...}` and brace-bodied arrow targets
    # (`(req, res) => {...}`, `async (req, res) => {...}`) starting exactly
    # at `value_start`. Concise arrow bodies without braces are not
    # modeled -- the endpoint is still emitted, just without extra params.
    private def function_target_body(content : String, value_start : Int32) : String?
      window_end = Math.min(content.size, value_start + 80)
      window = content[value_start...window_end]

      brace_search_from =
        if window.starts_with?("function")
          value_start
        elsif (arrow_idx = window.index("=>")) && !window[0...arrow_idx].includes?('{') && !window[0...arrow_idx].includes?(';')
          value_start + arrow_idx + 2
        else
          return
        end

      open_brace = content.index("{", brace_search_from)
      return unless open_brace
      return if open_brace - value_start > 120

      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      close_brace ? content[open_brace..close_brace] : nil
    end

    private def skip_ws(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
    end

    # ---------------------------------------------------------------------
    # Blueprint (convention-based) routes
    # ---------------------------------------------------------------------

    private def analyze_blueprints(root : String, result : Array(Endpoint))
      identities = {} of String => String
      controllers_prefix = "#{root}/api/controllers"
      models_prefix = "#{root}/api/models"

      get_files_by_prefix(controllers_prefix).each do |file|
        next unless js_source_file?(file)
        next unless file.starts_with?("#{controllers_prefix}/")
        rel = file[(controllers_prefix.size + 1)..]
        next if rel.empty?
        base = File.basename(rel)
        next if base.starts_with?(".")

        if !rel.includes?("/") && (md = base.match(CONTROLLER_FILE_RE))
          identity = md[1].downcase
          identities[identity] ||= file
          next
        end

        emit_action_shadow_route(file, rel, result)
      end

      get_files_by_prefix(models_prefix).each do |file|
        next unless js_source_file?(file)
        next unless file.starts_with?("#{models_prefix}/")
        rel = file[(models_prefix.size + 1)..]
        next if rel.empty? || rel.includes?("/")
        base = File.basename(rel)
        next unless md = base.match(MODEL_FILE_RE)

        identity = md[1].downcase
        identities[identity] ||= file
      end

      identities.each do |identity, source_file|
        BLUEPRINT_ROUTES.each do |method, sub_path|
          details = Details.new(PathInfo.new(source_file))
          endpoint = Endpoint.new("/#{identity}#{sub_path}", method, details)
          endpoint.push_param(Param.new("id", "", "path")) if sub_path == "/:id"
          result << endpoint
        end
      end
    end

    # A standalone "actions2" action file's URL is its path relative to
    # `api/controllers`, without the extension -- Sails' own convention
    # for referencing an action. `api/controllers/user/find-one.js`
    # becomes `/user/find-one`; `api/controllers/login.js` becomes
    # `/login`. Shadow routes respond to every HTTP verb until a custom
    # route in `config/routes.js` narrows them.
    private def emit_action_shadow_route(file : String, rel : String, result : Array(Endpoint))
      ext = File.extname(rel)
      identity_path = rel[0, rel.size - ext.size]
      return if identity_path.empty?

      url = "/#{identity_path}"
      HTTP_METHODS.each do |method|
        details = Details.new(PathInfo.new(file))
        result << Endpoint.new(url, method, details)
      end
    end

    private def js_source_file?(file : String) : Bool
      JS_SOURCE_EXTENSIONS.any? { |ext| file.ends_with?(ext) }
    end
  end
end
