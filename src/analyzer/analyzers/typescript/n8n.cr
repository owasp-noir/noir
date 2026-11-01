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

    # The keys whose truthy value turns the registry's auth middleware off.
    OPEN_KEYS = ["skipAuth", "allowUnauthenticated"]
    # `@GlobalScope('workflow:list')`, `@GlobalScope(SCOPE)`.
    SCOPE = /@(GlobalScope|ProjectScope|ApiKeyScope)\s*\(([^)]*)\)/
    ENTRY = /\A['"]?([A-Za-z_$][\w$]*)['"]?\s*:\s*([\s\S]+)\z/

    IDENTIFIER = /\A[A-Za-z_$][\w$]*\z/
    # `export { openOpts } from './route-opts'`: a barrel's re-export.
    NAMED_REEXPORT = /\bexport\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/

    # A route middleware named as a check of the caller: `scimAuth()`,
    # `getAuthMiddleware()`, `requireAuth`, `requireApiKey`, `verifyToken`,
    # `verifyWebhookSignature`, `validateApiKey`, `jwtMiddleware`. Not a
    # logger, another validator or a feature gate (`oauthCallbackLogger`,
    # `validateBody`, `isScimEnabledMiddleware`), whatever else its name holds.
    MIDDLEWARE_AUTH_NAME = /\A(?:authenticate|require(?:Auth|ApiKey)|isAuthenticated|ensureAuth|verify(?:Token|Signature|ApiKey|Auth|Jwt|\w*Signature)|validate(?:ApiKey|Token|Signature)|check(?:Auth|Token|ApiKey|Signature))|(?:\A|[a-z0-9])Auth(?:Middleware|Guard|Check)?\z|\Aauth(?:Middleware)?\z|[a-z0-9](?:Token|Signature|ApiKey)(?:Auth|Check|Middleware|Guard)\z|\Ajwt|Jwt/
    FEATURE_GATE_NAME    = /enabled|licensed|logger|\Alog|validat(?!e(?:ApiKey|Token|Signature))/i
    VERBS                = {"Del" => "DELETE", "QueryMethod" => "QUERY"}

    protected def route_decorated(endpoint : Endpoint, decorator_block : String, controller_decorator : String, route_path : String) : Nil
      scopes = decorator_block.scan(SCOPE).map { |m| "#{m[1]} #{m[2].strip.delete("'\"`")}" }
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

      entries, unread = route_options(decorator_block, endpoint.details.code_paths.first?.try(&.path), endpoint.method, route_path)
      opened = nil
      OPEN_KEYS.each do |key|
        value = entries[key]? || next
        next if value == "false"
        opened = value == "true" ? key : "#{key}: #{value}"
        break if value == "true"
      end
      if opened.nil?
        note = if unread
                 "; options `#{unread}` not read, they can open it"
               elsif (preview = entries["allowSkipPreviewAuth"]?) && preview != "false"
                 "; N8N_PREVIEW_MODE can open it through allowSkipPreviewAuth"
               end
        endpoint.add_tag(Tag.new("auth", "Protected by n8n auth cookie (ControllerRegistry auth middleware#{note})", TAGGER))
        return
      end
      middlewares = entries["middlewares"]?
      # `const middlewares = [cookieParser()];` handed on by name.
      if middlewares && middlewares.matches?(IDENTIFIER) && (file = endpoint.details.code_paths.first?.try(&.path))
        middlewares = const_array(middlewares, file) || middlewares
      end
      if middlewares && (guard = middleware_guard(middlewares))
        # `skipAuth: true` hands auth to the route's own middleware (SCIM's
        # bearer token).
        endpoint.add_tag(Tag.new("auth", "Protected by n8n route middleware #{guard} (#{opened})", TAGGER))
      elsif middlewares && (!middlewares.starts_with?('[') || middlewares.matches?(/[\[,]\s*\.\.\./))
        # `middlewares: getDynamicCredentialMiddlewares()`, `[...extra()]`:
        # a list built elsewhere, not read here.
        endpoint.add_tag(Tag.new("auth", "Protected by n8n route middlewares `#{middlewares}` (#{opened}; not read, they can admit anyone)", TAGGER))
      elsif opened.includes?(':')
        endpoint.add_tag(Tag.new("auth", "Protected by n8n auth cookie unless `#{opened}` is truthy (a setting can open it)", TAGGER))
      end
    end

    # The top-level keys of the options argument of the route decorator in
    # `block` that declared this route (`@Get('/public', { skipAuth: true })
    # @Get('/private')` gives `/private` none), inline or bound to a const in
    # this file or one it imports (`@Put('/Users/:id', scimRoute)`), and the
    # options it could not read (an unresolved const or spread), if any.
    private def route_options(block : String, file : String?, method : String, route_path : String) : Tuple(Hash(String, String), String?)
      decorators = [] of {String, Array(String)}
      block.scan(ROUTE_DECORATOR_RE) do |m|
        open = m.byte_end(0) - 1
        close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open) || next
        args = Noir::TopLevelSplit.split(block.byte_slice(open + 1, close - open - 1), ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
        decorators << {m[1], args}
      end
      own = decorators.select do |verb, args|
        (verb == "All" || (VERBS[verb]? || verb.upcase) == method) &&
          args[0]?.try(&.strip.strip("'\"`").strip('/')) == route_path.strip('/')
      end
      own = decorators if own.empty?

      entries = {} of String => String
      unread = nil
      own.each do |_, args|
        option = args[1]?.try(&.strip) || next
        object = if option.starts_with?('{')
                   Noir::JSRouteExtractor.strip_js_comments(option)
                 elsif file && option.matches?(IDENTIFIER)
                   const_object(option, file)
                 end
        if object
          unread ||= read_entries(object, file, entries, spread: true)
        else
          unread ||= option
        end
      end
      {entries, unread}
    end

    # Adds the top-level `key: value` pairs of `object` to `entries`; a
    # spread of a const is read one level down. Returns what it could not read.
    private def read_entries(object : String, file : String?, entries : Hash(String, String), spread : Bool) : String?
      unread = nil
      inner = object.strip.lchop('{').rchop('}')
      Noir::TopLevelSplit.split(inner, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |raw|
        entry = raw.strip
        next if entry.empty?
        if entry.starts_with?("...")
          name = entry[3..].strip
          spread_object = file && spread && name.matches?(IDENTIFIER) ? const_object(name, file) : nil
          if spread_object
            unread ||= read_entries(spread_object, file, entries, spread: false)
          else
            unread ||= entry
          end
        elsif m = entry.match(ENTRY)
          entries[m[1]] = m[2].strip
        elsif entry.matches?(IDENTIFIER)
          entries[entry] = entry # `{ skipAuth }`: set from a variable.
        end
      end
      unread
    end

    # The object literal bound to `const name = {…}` in `file` (comments
    # stripped), or in the relative module it imports `name` from, through
    # one barrel (`export { x } from './x'`).
    private def const_object(name : String, file : String, depth : Int32 = 0) : String?
      content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(file))
      # `export const scimRoute: { skipAuth: boolean; … } = {`: the type
      # annotation may itself be an object type.
      if m = content.match(/\b(?:const|let|var)\s+#{Regex.escape(name)}\b(?:\s*:\s*(?:\{[^{}]*\}|[^=;{]+))?\s*=\s*\{/)
        open = m.byte_end(0) - 1
        close = Noir::JSLiteralScanner.find_matching_brace_at_byte(content, open) || return
        return content.byte_slice(open, close - open + 1)
      end
      return if depth > 1
      {NAMED_IMPORT, NAMED_REEXPORT}.each do |pattern|
        content.scan(pattern) do |imp|
          declared = imported_name(imp[1], name) || next
          return unless imp[2].starts_with?('.')
          target = Noir::ImportGraph.resolve_relative_import(file, imp[2], boundary: import_boundary_for(file)) || return
          return const_object(declared, target, depth + 1)
        end
      end
      nil
    rescue
      nil
    end

    # The array literal bound to `const name = [...]` in `file`.
    private def const_array(name : String, file : String) : String?
      content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(file))
      m = content.match(/\b(?:const|let|var)\s+#{Regex.escape(name)}\b[^=;]*=\s*\[/) || return
      rest = content[(m.end(0) - 1)..]
      depth = 0
      rest.each_char_with_index do |char, idx|
        case char
        when '[' then depth += 1
        when ']'
          depth -= 1
          return rest[0..idx] if depth == 0
        end
      end
      nil
    rescue
      nil
    end

    # The first element of a `middlewares: [...]` list named as a caller check.
    private def middleware_guard(list : String) : String?
      return unless list.starts_with?('[')
      Noir::TopLevelSplit.split(list.lchop('[').rchop(']'), ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |element|
        name = element.strip.match(/\A[A-Za-z_$][\w$.]*/).try(&.[0]) || next
        last = name.split('.').last
        return name if last.matches?(MIDDLEWARE_AUTH_NAME) && !last.matches?(FEATURE_GATE_NAME)
      end
      nil
    end
  end
end
