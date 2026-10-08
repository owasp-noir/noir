require "../../engines/javascript_engine"
require "../../../miniparsers/wasp_extractor"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  # Wasp (https://wasp.sh) declares its server surface in the app config,
  # not in Express calls, and generates the server at build time. This maps
  # the declarations onto the routes the generator emits (checked against
  # waspc's server templates):
  #
  # - `api`: the declared method and path (`ALL` is Express `router.all`).
  # - `query` / `action`: `POST /operations/<kebab-case name>`.
  # - `crud`: `POST /crud/<name>/<get|get-all|create|update|delete>`.
  # - `route`: a client-side page, reported as a GET.
  # - `app.auth`: `GET /auth/me`, `POST /auth/logout` and the routes of
  #   each enabled auth method under `/auth/<provider>/`.
  #
  # `apiNamespace` only attaches middleware to a path; it does not prefix
  # the APIs under it, so it adds no route.
  #
  # Wasp's `auth` middleware resolves the session when a token is sent and
  # lets anonymous requests through, so `auth: true` on an api or
  # operation is not a guard. It is reported as a `wasp-auth` tag; only the
  # generated CRUD operations, which reject anonymous callers themselves,
  # get an `auth` tag.
  class Wasp < Analyzer::Javascript::JavascriptEngine
    analyzer_for "ts_wasp"

    TAGGER             = "wasp_analyzer"
    ALL_METHODS        = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
    HANDLER_EXTENSIONS = %w[.ts .tsx .js .jsx .mts .mjs .cts .cjs]
    ROOT_MARKERS       = %w[.wasproot main.wasp.ts main.wasp]
    CRUD_ROUTES        = {"get" => "get", "getAll" => "get-all", "create" => "create", "update" => "update", "delete" => "delete"}
    # `app.auth.methods` key → provider id used in the route.
    OAUTH_PROVIDERS = {"google" => "google", "gitHub" => "github", "keycloak" => "keycloak",
                       "slack" => "slack", "discord" => "discord", "microsoft" => "microsoft"}

    alias Spec = Noir::WaspExtractor::Spec
    record SpecFile, path : String, root : String, spec : Spec

    def analyze
      files = get_files_by_extensions([".wasp", ".ts"]).select { |path| wasp_config_file?(path) }.sort!
      return @result if files.empty?

      parsed = files.compact_map { |path| parse(path) }
      parsed.group_by(&.root).each do |root, group|
        analyze_app(root, group, files)
      end
      @result
    end

    private def wasp_config_file?(path : String) : Bool
      return false unless path.ends_with?(".wasp") || path.ends_with?(".wasp.ts")
      # `.wasp/` holds the generated app (and its copy of the spec types).
      !path.includes?("/.wasp/") && !path.includes?("/node_modules/")
    end

    private def parse(path : String) : SpecFile?
      content = read_file_content(path)
      spec = if path.ends_with?(".wasp")
               Noir::WaspExtractor.parse_dsl(content)
             elsif Noir::WaspExtractor.spec_module?(content)
               Noir::WaspExtractor.parse_spec(content)
             elsif Noir::WaspExtractor.config_module?(content)
               Noir::WaspExtractor.parse_config(content)
             end
      return if spec.nil? || spec.empty?
      SpecFile.new(path, project_root(path), spec)
    rescue e : IO::Error
      logger.debug "Wasp: cannot read #{path}: #{e.message}"
      nil
    end

    # The nearest directory holding `.wasproot` or the main config; a
    # `*.wasp.ts` under `src/features/x/` belongs to that app.
    private def project_root(path : String) : String
      dir = File.dirname(path)
      return dir if path.ends_with?(".wasp")
      current = dir
      8.times do
        return current if ROOT_MARKERS.any? { |marker| File.exists?(File.join(current, marker)) }
        parent = File.dirname(current)
        break if parent == current
        current = parent
      end
      dir
    end

    private def analyze_app(root : String, group : Array(SpecFile), files : Array(String))
      auth_enabled = group.any? { |file| file.spec.auth_enabled == true }
      auth_methods = auth_methods_for(root, group, files)

      group.each do |file|
        spec = file.spec
        spec.apis.each { |api| emit_api(file, api, auth_enabled) }
        spec.operations.each { |operation| emit_operation(file, operation, auth_enabled) }
        spec.cruds.each { |crud| emit_crud(file, crud, auth_enabled) }
        spec.routes.each { |route| emit_page(file, route) }
      end

      emit_auth_routes(group.find! { |file| file.spec.auth_enabled == true }, auth_methods) if auth_enabled
    end

    private def auth_methods_for(root : String, group : Array(SpecFile), files : Array(String)) : Array(String)
      methods = group.flat_map(&.spec.auth_methods).uniq!
      group.each do |file|
        ref = file.spec.auth_ref
        next unless ref && methods.empty?
        # The referenced config may sit in a `*.wasp.ts` that declares
        # nothing itself, so look through every config file of the app.
        files.each do |path|
          next unless path.starts_with?(root)
          literal = Noir::WaspExtractor.object_literal_for(read_file_content(path), ref)
          next unless literal
          methods = Noir::WaspExtractor.auth_methods(literal)
          break
        rescue IO::Error
          next
        end
      end
      methods
    end

    private def emit_api(file : SpecFile, api : Noir::WaspExtractor::Api, auth_enabled : Bool)
      handler = resolve_handler(file, api.fn)
      methods = api.method == "ALL" ? ALL_METHODS : [api.method]
      methods.each do |method|
        endpoint = Endpoint.new(api.path, method, details_for(file, api.line, handler))
        path_params(api.path).each { |name| endpoint.push_param(Param.new(name, "", "path")) }
        if found = handler
          body = found[:handler].body
          Noir::JSRouteExtractor.extract_query_params(body, endpoint)
          Noir::JSRouteExtractor.extract_body_params(body, endpoint)
          Noir::JSRouteExtractor.extract_header_params(body, endpoint)
          Noir::JSRouteExtractor.extract_cookie_params(body, endpoint)
          attach_callees(endpoint, found)
        end
        endpoint.add_tag(Tag.new("wasp-api", api.name, TAGGER))
        add_auth_tag(endpoint, api.auth, auth_enabled)
        @result << endpoint
      end
    end

    private def emit_operation(file : SpecFile, operation : Noir::WaspExtractor::Operation, auth_enabled : Bool)
      handler = resolve_handler(file, operation.fn)
      endpoint = Endpoint.new("/operations/#{kebab_case(operation.name)}", "POST", details_for(file, operation.line, handler))
      if found = handler
        Noir::WaspExtractor.operation_args(found[:handler]).each { |name| endpoint.push_param(Param.new(name, "", "json")) }
        attach_callees(endpoint, found)
      end
      endpoint.add_tag(Tag.new("wasp-operation", "#{operation.kind} #{operation.name}", TAGGER))
      add_auth_tag(endpoint, operation.auth, auth_enabled)
      @result << endpoint
    end

    private def emit_crud(file : SpecFile, crud : Noir::WaspExtractor::Crud, auth_enabled : Bool)
      crud.operations.each do |operation|
        handler = operation.overridden ? resolve_handler(file, operation.fn) : nil
        url = "/crud/#{crud.name}/#{CRUD_ROUTES[operation.name]}"
        endpoint = Endpoint.new(url, "POST", details_for(file, crud.line, handler))
        if found = handler
          Noir::WaspExtractor.operation_args(found[:handler]).each { |name| endpoint.push_param(Param.new(name, "", "json")) }
          attach_callees(endpoint, found)
        elsif !operation.overridden && operation.name.in?("get", "update", "delete")
          # The generated get/update/delete look the row up by `args.id`;
          # create passes `args` to Prisma as the row data.
          endpoint.push_param(Param.new("id", "", "json"))
        end
        endpoint.add_tag(Tag.new("wasp-crud", "#{crud.name}.#{operation.name}", TAGGER))
        if auth_enabled && !operation.public && !operation.overridden
          endpoint.add_tag(Tag.new("auth", "Protected by Wasp CRUD authentication", TAGGER))
        elsif operation.public
          endpoint.add_tag(Tag.new("wasp-auth", "isPublic: true", TAGGER))
        end
        @result << endpoint
      end
    end

    private def emit_page(file : SpecFile, route : Noir::WaspExtractor::PageRoute)
      endpoint = Endpoint.new(route.path, "GET", Details.new(PathInfo.new(file.path, route.line)))
      path_params(route.path).each { |name| endpoint.push_param(Param.new(name, "", "path")) }
      endpoint.add_tag(Tag.new("wasp-page", route.name, TAGGER))
      if route.auth_required
        endpoint.add_tag(Tag.new("wasp-auth-required", "Client-side redirect when logged out; not enforced by the server", TAGGER))
      end
      @result << endpoint
    end

    private def emit_auth_routes(file : SpecFile, methods : Array(String))
      details = Details.new(PathInfo.new(file.path, file.spec.app_line))
      push_auth_route(details, "/auth/me", "GET", "session")
      push_auth_route(details, "/auth/logout", "POST", "session")
      oauth = false
      methods.each do |method|
        case method
        when "usernameAndPassword"
          push_auth_route(details, "/auth/username/login", "POST", "username", %w[username password])
          push_auth_route(details, "/auth/username/signup", "POST", "username", %w[username password])
        when "email"
          push_auth_route(details, "/auth/email/login", "POST", "email", %w[email password])
          push_auth_route(details, "/auth/email/signup", "POST", "email", %w[email password])
          push_auth_route(details, "/auth/email/request-password-reset", "POST", "email", %w[email])
          push_auth_route(details, "/auth/email/reset-password", "POST", "email", %w[token password])
          push_auth_route(details, "/auth/email/verify-email", "POST", "email", %w[token])
        else
          if provider = OAUTH_PROVIDERS[method]?
            oauth = true
            push_auth_route(details, "/auth/#{provider}/login", "GET", provider)
            push_auth_route(details, "/auth/#{provider}/callback", "GET", provider, %w[code state], "query")
          end
        end
      end
      push_auth_route(details, "/auth/exchange-code", "POST", "oauth", %w[code]) if oauth
    end

    private def push_auth_route(details : Details, url : String, method : String, provider : String,
                                params : Array(String) = [] of String, param_type : String = "json")
      endpoint = Endpoint.new(url, method, details)
      params.each { |name| endpoint.push_param(Param.new(name, "", param_type)) }
      endpoint.add_tag(Tag.new("wasp-auth-route", provider, TAGGER))
      @result << endpoint
    end

    private def add_auth_tag(endpoint : Endpoint, declared : Bool?, auth_enabled : Bool)
      if declared == false
        endpoint.add_tag(Tag.new("wasp-auth", "auth: false; no session is resolved", TAGGER))
      elsif auth_enabled
        endpoint.add_tag(Tag.new("wasp-auth", "auth: true; session resolved when sent, anonymous calls reach the handler", TAGGER))
      end
    end

    private def details_for(file : SpecFile, line : Int32, handler : NamedTuple(path: String, source: String, name: String, handler: Noir::WaspExtractor::Handler)?) : Details
      details = Details.new(PathInfo.new(file.path, line))
      handler.try { |found| details.add_path(PathInfo.new(found[:path], found[:handler].line)) }
      details
    end

    private def attach_callees(endpoint : Endpoint, found : NamedTuple(path: String, source: String, name: String, handler: Noir::WaspExtractor::Handler))
      return if found[:name] == "default"
      attach_js_callees(endpoint, Noir::JSCalleeExtractor.callees_for_exported_function(found[:source], found[:path], found[:name]))
    end

    # Resolves `@src/x` (and the pre-0.12 `@server/x`) against the app
    # root, and relative Wasp Spec imports against the importing file.
    private def resolve_handler(file : SpecFile, fn : Noir::WaspExtractor::FnRef?)
      return unless fn
      base = if fn.from.starts_with?("@src/")
               File.join(file.root, "src", fn.from.lchop("@src/"))
             elsif fn.from.starts_with?("@server/")
               File.join(file.root, "src", "server", fn.from.lchop("@server/"))
             elsif fn.from.starts_with?(".")
               # Keep the scan's relative form; `expand_path` would make it absolute.
               Path.new(File.dirname(file.path)).join(fn.from).normalize.to_s
             end
      return unless base
      stem = base.sub(/\.(?:[cm]?[jt]sx?)\z/, "")
      candidates = [base] + HANDLER_EXTENSIONS.map { |ext| stem + ext } + HANDLER_EXTENSIONS.map { |ext| File.join(stem, "index#{ext}") }
      candidates.each do |path|
        next unless File.file?(path)
        source = read_file_content(path)
        if handler = Noir::WaspExtractor.handler(source, fn.name)
          return {path: path, source: source, name: fn.name, handler: handler}
        end
        return
      rescue IO::Error
        return
      end
      nil
    end

    # Express-style `:name` / `:name?` segments.
    private def path_params(path : String) : Array(String)
      path.split('/').compact_map do |segment|
        segment.match(/\A:([A-Za-z_]\w*)/).try(&.[1])
      end.uniq!
    end

    # waspc's `camelToKebabCase`: a dash before every uppercase letter that
    # follows a non-uppercase one, then lowercase (`getHTTPData` →
    # `get-httpdata`).
    def self.kebab_case(name : String) : String
      String.build do |io|
        previous : Char? = nil
        name.each_char do |char|
          io << '-' if previous && !previous.uppercase? && char.uppercase?
          io << char.downcase
          previous = char
        end
      end
    end

    private def kebab_case(name : String) : String
      self.class.kebab_case(name)
    end
  end
end
