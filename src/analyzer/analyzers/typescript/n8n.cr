require "./decorator_controller"

module Analyzer::Typescript
  # n8n's own decorator controllers (`@n8n/decorators`): `ControllerRegistry`
  # mounts a `@RestController('/workflows')` under the REST prefix
  # (`/rest`, `N8N_ENDPOINT_REST`), a `@RootLevelController('/x')` at the
  # root, and `PublicApiControllerRegistry` a `@PublicApiController('/tags')`
  # under `/api/v1` (`N8N_PUBLIC_API_ENDPOINT` + version). `@Get(path,
  # options)` and friends carry the verb; `@Param('id')`, `@Query` and
  # `@Body` (bare or called) the params.
  #
  # Auth is the registries' rule, not a middleware argument: every REST and
  # root route gets `authService.createAuthMiddleware` unless its options
  # say `skipAuth: true` or `allowUnauthenticated: true`; every public API
  # route gets the API-key/OAuth middleware. A `@GlobalScope` /
  # `@ProjectScope` check refuses an unauthenticated caller on its own.
  class N8n < DecoratorController
    analyzer_for "ts_n8n"

    TAGGER = "n8n_analyzer"

    IMPORT_RE   = /(?:\bfrom|\brequire\s*\()\s*['"]@n8n\/decorators['"]/
    CONTROLLERS = ["RestController", "RootLevelController", "PublicApiController"]
    PREFIXES    = {"RestController" => "/rest", "PublicApiController" => "/api/v1"}
    PARAMS      = {
      "Param" => {"path", nil},
      "Query" => {"query", "query"},
      "Body"  => {"body", "body"},
    } of String => Tuple(String, String?)
    PARAM_RE = param_decorator_re(PARAMS.keys)

    # `@Body payload: Dto` — the bare form, applied as a decorator itself.
    BARE_ARG = /@(Body|Query|Param)(?!\s*\()(?=\s)/

    # `skipAuth: true` / `allowUnauthenticated: true` in the route options.
    OPEN_OPTION = /\b(skipAuth|allowUnauthenticated)\s*:\s*([^,}\s][^,}]*)/
    SCOPE       = /@(GlobalScope|ProjectScope|ApiKeyScope)\s*\(\s*(['"`])([^'"`]+)\2/
    MIDDLEWARES = /\bmiddlewares\s*:\s*\[([^\]]*)\]/

    IDENTIFIER = /\A[A-Za-z_$][\w$]*\z/
    # Blanked before the options are read: `{ summary: 'skipAuth: true' }`.
    STRING_LITERAL = /'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\.)*`/

    MIDDLEWARE_AUTH_NAME = /auth|token|signature|apikey/i
    FEATURE_GATE_NAME    = /enabled|licensed|\Alog/i

    protected def controller_decorators : Array(String)
      CONTROLLERS
    end

    protected def app_root_markers : Array(String)
      ["\"@n8n/decorators\""]
    end

    # The registries' prefixes are fixed: no other file sets one.
    protected def prefix_outside_owned_sources? : Bool
      false
    end

    private def parse_controller_decorator(text : String, literal_values : Hash(String, Array(String)), name : String) : Array(String)?
      paths = super || return
      prefix = PREFIXES[name]? || return paths
      paths.map { |path| combine_paths(prefix, path) }
    end

    private def dto_params(method_params : String, file_path : String) : Hash(String, Array(String))
      super(called_args(method_params), file_path)
    end

    private def extract_decorator_parameters(method_params : String, endpoint : Endpoint,
                                             dto_fields : Hash(String, Array(String)) = {} of String => Array(String))
      dto_fields.each do |param_type, names|
        names.each { |name| endpoint.push_param(Param.new(name, "", param_type)) }
      end
      called_args(method_params).scan(PARAM_RE) do |match|
        type, fallback = PARAMS[match[1]]
        # A resolved DTO already named its fields.
        next if fallback && dto_fields.has_key?(type)
        name = match[3]? || fallback || match[4]?
        endpoint.push_param(Param.new(name, "", type)) if name
      end
    end

    private def called_args(method_params : String) : String
      method_params.includes?('@') ? method_params.gsub(BARE_ARG, "@\\1()") : method_params
    end

    protected def route_decorated(endpoint : Endpoint, decorator_block : String, controller_decorator : String) : Nil
      scopes = decorator_block.scan(SCOPE).map { |m| "#{m[1]} #{m[3]}" }
      scoped = scopes.empty? ? "" : " (#{scopes.join(", ")})"
      if controller_decorator == "PublicApiController"
        endpoint.add_tag(Tag.new("auth", "Protected by n8n public API authentication (API key or OAuth token)#{scoped}", TAGGER))
        return
      end
      # The scope middleware throws `UnauthenticatedError` with no user.
      unless scopes.empty?
        endpoint.add_tag(Tag.new("auth", "Protected by n8n scope check#{scoped}", TAGGER))
        return
      end

      options = route_options(decorator_block, endpoint.details.code_paths.first?.try(&.path)).gsub(STRING_LITERAL, "''")
      opened = nil
      options.scan(OPEN_OPTION) do |m|
        value = m[2].strip
        next if value == "false"
        opened = value == "true" ? m[1] : "#{m[1]}: #{value}"
        break if value == "true"
      end
      if opened.nil?
        endpoint.add_tag(Tag.new("auth", "Protected by n8n auth cookie (ControllerRegistry auth middleware)", TAGGER))
      elsif guard = middleware_guard(options)
        # `skipAuth: true` hands auth to the route's own middleware (SCIM's
        # bearer token).
        endpoint.add_tag(Tag.new("auth", "Protected by n8n route middleware #{guard} (#{opened})", TAGGER))
      elsif opened.includes?(':')
        endpoint.add_tag(Tag.new("auth", "Protected by n8n auth cookie unless `#{opened}` is truthy (a setting can open it)", TAGGER))
      end
    end

    # The options argument of every route decorator in `block`, inline or
    # bound to a const in this file or a relative import (`@Put('/Users/:id',
    # scimRoute)`).
    private def route_options(block : String, file : String?) : String
      String.build do |io|
        block.scan(ROUTE_DECORATOR_RE) do |m|
          open = m.byte_end(0) - 1
          close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open) || next
          args = Noir::TopLevelSplit.split(block.byte_slice(open + 1, close - open - 1), ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
          option = args[1]?.try(&.strip) || next
          if option.starts_with?('{')
            io << option << '\n'
          elsif file && option.matches?(IDENTIFIER)
            const_object(option, file).try { |object| io << object << '\n' }
          end
        end
      end
    end

    # The object literal bound to `const name = {…}` in `file`, or in the
    # relative module `file` imports `name` from.
    private def const_object(name : String, file : String, depth : Int32 = 0) : String?
      content = read_file_content(file)
      # `export const scimRoute: { skipAuth: boolean; … } = {`: the type
      # annotation may itself be an object type.
      if m = content.match(/\b(?:const|let|var)\s+#{Regex.escape(name)}\b(?:\s*:\s*(?:\{[^{}]*\}|[^=;{]+))?\s*=\s*\{/)
        open = m.byte_end(0) - 1
        close = Noir::JSLiteralScanner.find_matching_brace_at_byte(content, open) || return
        return content.byte_slice(open, close - open + 1)
      end
      return if depth > 0
      content.scan(NAMED_IMPORT) do |imp|
        declared = imported_name(imp[1], name) || next
        return unless imp[2].starts_with?('.')
        target = Noir::ImportGraph.resolve_relative_import(file, imp[2], boundary: import_boundary_for(file)) || return
        return const_object(declared, target, depth + 1)
      end
      nil
    rescue
      nil
    end

    # ponytail: a `middlewares` element is judged by its name, not its
    # definition (`scimAuth()`, `rejectUnauthenticated`); a feature gate
    # (`isApiKeyAuthEnabledMiddleware`) is not a caller check.
    private def middleware_guard(options : String) : String?
      list = options.match(MIDDLEWARES).try(&.[1]) || return
      Noir::TopLevelSplit.split(list, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |element|
        name = element.strip.match(/\A[A-Za-z_$][\w$.]*/).try(&.[0]) || next
        return name if name.matches?(MIDDLEWARE_AUTH_NAME) && !name.matches?(FEATURE_GATE_NAME)
      end
      nil
    end
  end
end
