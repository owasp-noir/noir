require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/import_graph"
require "../../../utils/url_path"
require "../../../utils/top_level_split"

module Analyzer::Javascript
  # Feathers.js (https://feathersjs.com) is service-based rather than
  # route-based: registering a service at a path auto-generates REST
  # verbs from whichever of the standard CRUD methods the service
  # implements.
  #
  #     app.use('/messages', new MessageService())
  #     app.service('messages').hooks({ ... })
  #
  #   find(params)          -> GET    /messages
  #   get(id, params)       -> GET    /messages/:id
  #   create(data, params)  -> POST   /messages
  #   update(id, data, params) -> PUT /messages/:id
  #   patch(id, data, params)  -> PATCH /messages/:id
  #   remove(id, params)    -> DELETE /messages/:id
  #
  # `app.use(path, service, options)` accepts an optional third
  # argument whose `methods:` array is the *authoritative* list of
  # externally exposed methods when present (v5 "Dove" API) — it is
  # honoured here as an intersection against whatever methods were
  # otherwise detected/assumed. The `path` and `methods:` value are
  # both frequently bare identifiers pointing at a sibling
  # `<name>.shared.ts` module in the current (v5/"Dove") CLI generator
  # layout (`export const messagePath = 'messages'`, `export const
  # messageMethods = ['find', 'get', ...] as const`) rather than
  # inline literals — both are resolved the same one-`import`-hop way
  # as the service class itself.
  #
  # ## False-positive risk
  #
  # `app.use('/path', someExpression)` is also the generic Express
  # middleware/router-mount idiom, and Express coexists with Feathers
  # in the same JS/Node ecosystem noir already supports. To avoid
  # stealing routes from a plain Express app (or a sibling Express
  # app in a monorepo), a `.use()` call is only treated as a Feathers
  # service registration when the second argument is structurally
  # service-shaped:
  #
  #   * `new SomeClass(...)`             — Express never mounts a
  #     freshly-constructed instance this way; routers/middleware are
  #     always factory calls (`express.Router()`, `cors()`, ...)
  #     without `new`.
  #   * an inline object literal `{ ... }`.
  #   * a bare identifier that resolves (same-file or one `require`/
  #     `import` hop, via `Noir::ImportGraph`) to a class or object
  #     literal — but NOT to `express.Router()`/`Router()`.
  #   * a bare identifier that cannot be resolved at all, but the same
  #     file also calls `app.service(<same path>)` — an API Express
  #     apps never have, since `.service()` doesn't exist on a plain
  #     Express `app`.
  #
  # A `identifier(...)` / `member.expr(...)` call (the shape of
  # `express.Router()`, `cors()`, `express.static(...)`, ...) is never
  # accepted, so ordinary Express middleware mounting is left alone.
  #
  # When the service expression resolves to a real class/object body,
  # only the CRUD methods that body actually defines are emitted — a
  # service that only implements `find`/`get` does not get `create`/
  # `update`/`patch`/`remove` fabricated for it. The one exception is
  # a class that `extends` one of the well-known Feathers database
  # adapters (`KnexService`, `MongoDBService`, `MemoryService`, ...) —
  # those always implement the full CRUD set themselves regardless of
  # which methods the subclass overrides, which is how the official
  # CLI generator's default `<name>.class.ts` looks
  # (`export class MessageService extends KnexService<...> {}`, no
  # method bodies at all).
  #
  # When the expression can't be resolved to a body at all (external
  # package, dynamic value, ...) but the structural evidence above is
  # still strong enough to be confident this IS a Feathers
  # registration, the full 6-verb CRUD set is emitted as a documented,
  # deliberately conservative fallback — never for a body we DID
  # inspect, found to extend nothing adapter-like, and found zero
  # CRUD-shaped methods in, which is treated as a real negative
  # (nothing emitted) rather than a fallback trigger.
  class Feathers < JavascriptEngine
    analyzer_for "js_feathers"

    JS_EXTENSIONS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx"]

    CRUD_METHODS = %w[find get create update patch remove]

    # method name => {HTTP verb, needs a trailing /:id segment}
    CRUD_VERB = {
      "find"   => {"GET", false},
      "get"    => {"GET", true},
      "create" => {"POST", false},
      "update" => {"PUT", true},
      "patch"  => {"PATCH", true},
      "remove" => {"DELETE", true},
    }

    BODY_METHODS = Set{"create", "update", "patch"}

    # The officially documented Feathers database-adapter service base
    # classes (https://feathersjs.com/api/databases/adapters) — every
    # one of these implements the full CRUD set itself, so a subclass
    # that overrides none (or only some) of them still exposes all six
    # externally, unless narrowed by an explicit `methods:` option.
    KNOWN_ADAPTER_BASE_CLASSES = Set{
      "Service", "AdapterService",
      "KnexService", "MongoDBService", "MemoryService", "SequelizeService",
      "NeDBService", "MikroOrmService", "ObjectionService", "PrismaService",
      "RethinkDBService", "MongooseService", "FeathersSequelize",
    }

    # Crystal recompiles an interpolated regex literal on every
    # evaluation; these are keyed by the (small, fixed) CRUD method
    # name set, so build them once at load time rather than per call.
    # `m` makes `^` match at each line start within a multi-line body,
    # not just the start of the whole string.
    METHOD_PAREN_RE = CRUD_METHODS.to_h { |m| {m, /^[ \t]*(?:public\s+|private\s+|protected\s+|static\s+|async\s+)*#{m}\s*\(/m} }
    METHOD_COLON_RE = CRUD_METHODS.to_h { |m| {m, /^[ \t]*#{m}\s*:/m} }

    USE_CALL_RE = /\.use\s*\(/

    QUERY_PARAM_RE       = /\bparams\.query\.(\w+)|\bparams\.query\[\s*['"](\w+)['"]\s*\]/
    QUERY_DESTRUCTURE_RE = /(?:const|let|var)\s*\{\s*([^}]+)\}\s*=\s*params\.query\b/
    HEADER_PARAM_RE      = /\bparams\.headers\.(\w+)|\bparams\.headers\[\s*['"]([\w-]+)['"]\s*\]/

    # A resolved service body: `content`/`path` are the file the body
    # actually lives in (which may differ from the `.use()` call's own
    # file after a cross-file `require`/`import` hop), `open_brace`/
    # `close_brace` bound the body, and `adapter_backed` records
    # whether the body is a class `extends`-ing a well-known Feathers
    # database adapter (see `KNOWN_ADAPTER_BASE_CLASSES`).
    private record ServiceBody, content : String, path : String, open_brace : Int32, close_brace : Int32, adapter_backed : Bool = false

    def analyze
      result = [] of Endpoint
      include_callee = callees_needed?

      parallel_file_scan(JS_EXTENSIONS) do |path|
        content = read_file_content(path)
        next unless content.matches?(USE_CALL_RE)

        scan_file(path, content, result, include_callee)
      end

      result
    end

    # ---------------------------------------------------------------
    # Per-file scan: find every `<recv>.use(<path>, <service>[,
    # <options>])` call and, when it structurally looks like a
    # Feathers service registration, emit its CRUD endpoints.
    # ---------------------------------------------------------------
    private def scan_file(path : String, content : String, result : Array(Endpoint), include_callee : Bool)
      content.scan(/\w+\s*\.\s*use\s*\(/) do |m|
        call_start = m.begin(0)
        next unless call_start
        open_paren = call_start + m[0].size - 1
        close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
        next unless close_paren

        args = split_top_level_args(content, open_paren + 1, close_paren)
        next if args.size < 2

        service_path = resolve_path_literal(content, path, args[0][0])
        next unless service_path

        service_text, service_start = args[1]

        methods, region = resolve_service_methods(content, path, service_text, service_start, service_path, args[0][0])
        next unless methods
        next if methods.empty?

        if args.size >= 3
          if opts_methods = parse_methods_option(content, path, args[2][0])
            methods = methods & opts_methods
            next if methods.empty?
          end
        end

        line = content[0...call_start].count('\n') + 1
        emit_service_endpoints(result, path, service_path, methods, region, line, include_callee)
      end
    end

    # Classifies the service expression and returns {methods, region}
    # where `region` is a `ServiceBody` when a real body was located
    # (nil for the documented full-CRUD fallback). Returns {nil, nil}
    # when the call should not be treated as a Feathers registration
    # at all.
    private def resolve_service_methods(content : String, path : String, service_text : String, service_start : Int32,
                                        service_path : String, raw_path_arg : String) : Tuple(Set(String)?, ServiceBody?)
      text = service_text.strip

      if m = text.match(/\Anew\s+([A-Za-z_$][\w$]*)\s*\(/)
        class_name = m[1]
        region = find_class_body(content, path, class_name)
        if region
          return {methods_for_region(region), region}
        end
        # `new X(...)` alone is strong-enough structural evidence to
        # trust even without locating X's body (e.g. X comes from an
        # external npm package) — the documented fallback.
        return {Set(String).new(CRUD_METHODS), nil}
      end

      if text.starts_with?("{")
        open_brace = service_start + (service_text.index("{") || 0)
        close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
        return {nil, nil} unless close_brace
        region = ServiceBody.new(content, path, open_brace, close_brace)
        return {methods_for_region(region), region}
      end

      if text.matches?(/\A[A-Za-z_$][\w$]*\z/)
        name = text
        return {nil, nil} if identifier_is_router_factory?(content, name)

        # `const authentication = new AuthenticationService(app); ...;
        # app.use('authentication', authentication)` — a locally
        # instantiated service assigned to a variable before being
        # passed to `.use()`, rather than inlined as `new X(...)`
        # directly. Resolve the SAME way as the inline `new X(...)`
        # case, including its external-package fallback.
        if class_name = local_new_instance_class(content, name)
          region = find_class_body(content, path, class_name)
          return {methods_for_region(region), region} if region
          return {Set(String).new(CRUD_METHODS), nil}
        end

        region = find_object_literal_same_file(content, path, name) ||
                 find_class_or_object_cross_file(content, path, name)
        if region
          return {methods_for_region(region), region}
        end

        if service_call_co_occurs?(content, service_path, raw_path_arg)
          return {Set(String).new(CRUD_METHODS), nil}
        end

        return {nil, nil}
      end

      # `identifier(...)`, `a.b(...)`, ternaries, etc. — the shape of
      # generic Express middleware/router mounting. Never treated as a
      # Feathers registration.
      {nil, nil}
    end

    # A `ServiceBody` that extends a known adapter always exposes the
    # full CRUD set (overriding a method customises it, it doesn't
    # remove the ones the adapter base already implements). Otherwise
    # only the explicitly-detected methods count — never fabricated.
    private def methods_for_region(region : ServiceBody) : Set(String)
      return Set(String).new(CRUD_METHODS) if region.adapter_backed
      detect_methods(region.content[region.open_brace...region.close_brace])
    end

    private def detect_methods(body : String) : Set(String)
      found = Set(String).new
      CRUD_METHODS.each do |m|
        if body.matches?(METHOD_PAREN_RE[m]) || body.matches?(METHOD_COLON_RE[m])
          found << m
        end
      end
      found
    end

    # ---------------------------------------------------------------
    # Body resolution helpers
    # ---------------------------------------------------------------

    private def find_class_body(content : String, path : String, class_name : String) : ServiceBody?
      if region = named_class_region(content, class_name)
        return ServiceBody.new(content, path, region[0], region[1], region[2])
      end

      if resolved = resolve_identifier_via_import(content, path, class_name)
        resolved_content, resolved_path, exported_name = resolved
        if region = named_class_region(resolved_content, exported_name)
          return ServiceBody.new(resolved_content, resolved_path, region[0], region[1], region[2])
        end
        if region = sole_class_region(resolved_content)
          return ServiceBody.new(resolved_content, resolved_path, region[0], region[1], region[2])
        end
        if region = default_export_object_region(resolved_content)
          return ServiceBody.new(resolved_content, resolved_path, region[0], region[1])
        end
      end

      nil
    end

    private def find_object_literal_same_file(content : String, path : String, name : String) : ServiceBody?
      esc = Regex.escape(name)
      m = content.match(/(?:const|let|var)\s+#{esc}\s*=\s*\{/)
      return unless m
      match_end = m.end(0)
      return unless match_end
      open_brace = match_end - 1
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      return unless close_brace
      ServiceBody.new(content, path, open_brace, close_brace)
    end

    private def find_class_or_object_cross_file(content : String, path : String, name : String) : ServiceBody?
      resolved = resolve_identifier_via_import(content, path, name)
      return unless resolved
      resolved_content, resolved_path, exported_name = resolved

      if region = named_class_region(resolved_content, exported_name)
        return ServiceBody.new(resolved_content, resolved_path, region[0], region[1], region[2])
      end
      if region = sole_class_region(resolved_content)
        return ServiceBody.new(resolved_content, resolved_path, region[0], region[1], region[2])
      end
      if region = default_export_object_region(resolved_content)
        return ServiceBody.new(resolved_content, resolved_path, region[0], region[1])
      end
      nil
    end

    # {open_brace, close_brace, adapter_backed}
    private def named_class_region(content : String, class_name : String) : Tuple(Int32, Int32, Bool)?
      esc = Regex.escape(class_name)
      m = content.match(/\bclass\s+#{esc}\b[^{]*\{/)
      return unless m
      match_end = m.end(0)
      return unless match_end
      open_brace = match_end - 1
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      return unless close_brace
      {open_brace, close_brace, adapter_backed_header?(m[0])}
    end

    SOLE_CLASS_RE = /\bclass\s+([A-Za-z_$][\w$]*)\b[^{]*\{/

    # Best-effort: a required file that defines exactly one class is
    # almost always the service class file (the generator's
    # `<name>.class.js` convention), even when the local import alias
    # doesn't match the exported name.
    private def sole_class_region(content : String) : Tuple(Int32, Int32, Bool)?
      matches = content.scan(SOLE_CLASS_RE)
      return unless matches.size == 1
      m = matches[0]
      match_end = m.end(0)
      return unless match_end
      open_brace = match_end - 1
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      return unless close_brace
      {open_brace, close_brace, adapter_backed_header?(m[0])}
    end

    private def default_export_object_region(content : String) : Tuple(Int32, Int32)?
      m = content.match(/module\.exports\s*=\s*\{/)
      return unless m
      match_end = m.end(0)
      return unless match_end
      open_brace = match_end - 1
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      return unless close_brace
      {open_brace, close_brace}
    end

    # `header` is the full class declaration text, from `class Name`
    # through the opening `{`. A TypeScript generic bound
    # (`<T extends Params>`) can itself contain the word `extends`, so
    # the REAL base class — if any — is the LAST `extends X` in the
    # header (the generic parameter list, if present, always closes
    # before the real `extends` clause).
    private def adapter_backed_header?(header : String) : Bool
      matches = header.scan(/\bextends\s+([A-Za-z_$][\w$]*)/)
      return false if matches.empty?
      base_name = matches.last[1]?
      !base_name.nil? && KNOWN_ADAPTER_BASE_CLASSES.includes?(base_name)
    end

    # Resolves `name` to {target_content, target_path, exported_name}
    # by following exactly one `require`/`import` hop from `content`
    # (mirrors the one-level-deep philosophy of `Noir::ImportGraph`).
    # Only relative specifiers (`./...`, `../...`) are followed —
    # external npm packages have no source to inspect.
    private def resolve_identifier_via_import(content : String, path : String, name : String) : Tuple(String, String, String)?
      esc = Regex.escape(name)

      spec = nil
      exported_name = name

      if m = content.match(/(?:const|let|var)\s+#{esc}\s*=\s*require\(\s*['"]([^'"]+)['"]\s*\)/)
        spec = m[1]
      elsif m = content.match(/import\s+#{esc}\s+from\s+['"]([^'"]+)['"]/)
        spec = m[1]
      else
        # A real source file typically carries several destructured
        # `require`/named `import` statements, and the target name may
        # be in any of them (not necessarily the first) — e.g. a
        # generated Feathers service file imports `authenticate` from
        # `@feathersjs/authentication` before it imports the service
        # class itself from `./x.class`. `String#match` only ever
        # inspects the FIRST occurrence, so scan every occurrence of
        # each destructuring shape until one actually contains `name`.
        content.scan(/(?:const|let|var)\s*\{\s*([^}]*)\}\s*=\s*require\(\s*['"]([^'"]+)['"]\s*\)/) do |dm|
          next unless dm.size >= 3
          list = dm[1]
          next unless list.split(",").any? { |entry| destructure_local_name(entry) == name }
          spec = dm[2]
          exported_name = destructure_exported_name(list, name)
        end

        if spec.nil?
          content.scan(/import\s*\{\s*([^}]*)\}\s*from\s*['"]([^'"]+)['"]/) do |dm|
            next unless dm.size >= 3
            list = dm[1]
            next unless list.split(",").any? { |entry| destructure_local_name(entry) == name }
            spec = dm[2]
            exported_name = destructure_exported_name(list, name)
          end
        end
      end

      return unless spec
      return unless spec.starts_with?("./") || spec.starts_with?("../")

      resolved_path = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: @base_path)
      return unless resolved_path

      begin
        resolved_content = read_file_content(resolved_path)
      rescue
        return
      end

      {resolved_content, resolved_path, exported_name}
    end

    private def destructure_local_name(entry : String) : String
      entry = entry.strip
      return "" if entry.empty?
      entry.includes?(":") ? entry.split(":").last.strip : entry
    end

    private def destructure_exported_name(list : String, local_name : String) : String
      list.split(",").each do |entry|
        entry = entry.strip
        next if entry.empty?
        if entry.includes?(":")
          parts = entry.split(":").map(&.strip)
          exported = parts[0]? || local_name
          local = parts[1]? || exported
          return exported if local == local_name
        elsif entry == local_name
          return entry
        end
      end
      local_name
    end

    private def identifier_is_router_factory?(content : String, name : String) : Bool
      esc = Regex.escape(name)
      content.matches?(/(?:const|let|var)\s+#{esc}\s*=\s*(?:express\.Router\s*\(\s*\)|Router\s*\(\s*\))/)
    end

    # `const <name> = new ClassName(...)` — the class name a local
    # variable was directly instantiated from, if any.
    private def local_new_instance_class(content : String, name : String) : String?
      esc = Regex.escape(name)
      m = content.match(/(?:const|let|var)\s+#{esc}\s*=\s*new\s+([A-Za-z_$][\w$]*)\s*\(/)
      m ? m[1] : nil
    end

    # `raw_path_arg` is the ORIGINAL (unresolved) text of `.use()`'s
    # first argument — either a quoted literal or the bare identifier
    # it came from — so a co-located `app.service(messagePath)` call
    # (v5/"Dove" style, the path itself is a shared constant) is
    # recognised alongside the classic `app.service('messages')` form.
    private def service_call_co_occurs?(content : String, service_path : String, raw_path_arg : String) : Bool
      normalized = service_path.lstrip('/')
      literal_candidates = Set{service_path, normalized, "/#{normalized}"}
      return true if literal_candidates.any? do |candidate|
                       content.matches?(/\.service\(\s*['"]#{Regex.escape(candidate)}['"]\s*\)/)
                     end

      raw = raw_path_arg.strip
      return false unless raw.matches?(/\A[A-Za-z_$][\w$]*\z/)
      content.matches?(/\.service\(\s*#{Regex.escape(raw)}\s*\)/)
    end

    # `.use()`'s first argument: a quoted string literal, or a bare
    # identifier resolved (same-file, or one `require`/`import` hop)
    # to one — the v5/"Dove" CLI generator centralises each service's
    # path in a sibling `<name>.shared.ts`'s `export const xPath =
    # 'x'`, referenced by identifier at the call site.
    private def resolve_path_literal(content : String, path : String, arg_text : String) : String?
      if literal = quoted_literal(arg_text)
        return literal
      end

      name = arg_text.strip
      return unless name.matches?(/\A[A-Za-z_$][\w$]*\z/)

      if literal = same_file_string_const(content, name)
        return literal
      end

      if resolved = resolve_identifier_via_import(content, path, name)
        resolved_content, _, exported_name = resolved
        return same_file_string_const(resolved_content, exported_name)
      end

      nil
    end

    private def same_file_string_const(content : String, name : String) : String?
      esc = Regex.escape(name)
      m = content.match(/(?:export\s+)?(?:const|let|var)\s+#{esc}\s*(?::\s*[^=]+)?=\s*['"]([^'"]+)['"]/)
      m ? m[1] : nil
    end

    # `{ methods: ['find', 'get'] }` — the v5 `app.use` options
    # argument. The array itself may also be a bare identifier
    # resolved the same one-hop way as the path
    # (`export const xMethods = ['find', ...] as const`). Returns nil
    # when the argument isn't (or doesn't contain, or can't resolve) a
    # `methods:` value, so callers can distinguish "no options given"
    # from "options given with an empty list".
    private def parse_methods_option(content : String, path : String, options_text : String) : Set(String)?
      m = options_text.match(/\bmethods\s*:\s*(\[[^\]]*\]|[A-Za-z_$][\w$]*)/)
      return unless m
      raw = m[1]

      list_text =
        if raw.starts_with?("[")
          raw[1..-2]
        else
          resolve_identifier_array_text(content, path, raw)
        end
      return unless list_text

      found = Set(String).new
      list_text.scan(/['"](\w+)['"]/) do |lm|
        found << lm[1].downcase if lm.size > 1 && CRUD_METHODS.includes?(lm[1].downcase)
      end
      found
    end

    private def resolve_identifier_array_text(content : String, path : String, name : String) : String?
      if text = same_file_array_const(content, name)
        return text
      end

      if resolved = resolve_identifier_via_import(content, path, name)
        resolved_content, _, exported_name = resolved
        return same_file_array_const(resolved_content, exported_name)
      end

      nil
    end

    private def same_file_array_const(content : String, name : String) : String?
      esc = Regex.escape(name)
      m = content.match(/(?:export\s+)?(?:const|let|var)\s+#{esc}\s*(?::\s*[^=]+)?=\s*\[([^\]]*)\]/)
      m ? m[1] : nil
    end

    # ---------------------------------------------------------------
    # Endpoint construction
    # ---------------------------------------------------------------

    private def emit_service_endpoints(result : Array(Endpoint), path : String, service_path : String,
                                       methods : Set(String), region : ServiceBody?,
                                       line : Int32, include_callee : Bool)
      base_url = normalize_service_path(service_path)
      method_regions = region ? collect_method_regions(region.content, region.open_brace, region.close_brace) : {} of String => Tuple(Int32, Int32)

      CRUD_METHODS.each do |crud_method|
        next unless methods.includes?(crud_method)
        verb, needs_id = CRUD_VERB[crud_method]
        url = needs_id ? Noir::URLPath.join_trimmed(base_url, ":id") : base_url

        endpoint = Endpoint.new(url, verb, Details.new(PathInfo.new(path, line)))

        url.scan(/:(\w+)/) do |pm|
          endpoint.push_param(Param.new(pm[1], "", "path")) if pm.size > 0
        end
        endpoint.push_param(Param.new("body", "", "json")) if BODY_METHODS.includes?(crud_method)

        if region && (mr = method_regions[crud_method]?)
          bc = region.content
          method_body = bc[(mr[0] + 1)...mr[1]]
          extract_method_params(endpoint, method_body)
          if include_callee
            method_line = bc[0...mr[0]].count('\n') + 1
            attach_method_callees(endpoint, method_body, region.path, method_line)
          end
        end

        result << endpoint
      end
    end

    private def normalize_service_path(service_path : String) : String
      trimmed = service_path.strip
      return "/" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    # Locates each implemented CRUD method's own function body inside
    # [region_start, region_end) — paren-form definitions only
    # (`method(...) { ... }`), so an arrow-function-with-colon-value
    # definition (`find: (params) => expr`, no guaranteed braces) is
    # counted as "implemented" by `detect_methods` but simply has no
    # per-method param/callee extraction here.
    private def collect_method_regions(content : String, region_start : Int32, region_end : Int32) : Hash(String, Tuple(Int32, Int32))
      region = content[region_start...region_end]
      found = {} of String => Tuple(Int32, Int32)

      CRUD_METHODS.each do |m|
        match = region.match(METHOD_PAREN_RE[m])
        next unless match
        rel_start = match.begin(0)
        next unless rel_start
        abs_start = region_start + rel_start

        open_paren = content.index('(', abs_start)
        next unless open_paren
        close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
        next unless close_paren

        open_brace = content.index('{', close_paren)
        next unless open_brace
        close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
        next unless close_brace

        found[m] = {open_brace, close_brace}
      end

      found
    end

    private def extract_method_params(endpoint : Endpoint, body : String)
      body.scan(QUERY_PARAM_RE) do |m|
        name = (m[1]? || m[2]?).to_s
        push_unique_param(endpoint, Param.new(name, "", "query")) unless name.empty?
      end
      body.scan(QUERY_DESTRUCTURE_RE) do |m|
        next unless m.size > 0
        (m[1]? || "").split(",").each do |raw|
          name = raw.split("=").first.strip.split(":").first.strip
          push_unique_param(endpoint, Param.new(name, "", "query")) unless name.empty?
        end
      end
      body.scan(HEADER_PARAM_RE) do |m|
        name = (m[1]? || m[2]?).to_s
        push_unique_param(endpoint, Param.new(name, "", "header")) unless name.empty?
      end
    end

    private def push_unique_param(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      endpoint.push_param(param)
    end

    private def attach_method_callees(endpoint : Endpoint, body : String, path : String, line : Int32)
      callees = Noir::JSCalleeExtractor.callees_for_function_body(body, path, line, language: javascript_source_language(path))
      callees.each do |name, callee_path, callee_line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
      end
    end

    # ---------------------------------------------------------------
    # Top-level call-argument splitting (quote/paren/brace/bracket
    # depth aware), local to this analyzer.
    # ---------------------------------------------------------------
    private def split_top_level_args(content : String, start_pos : Int32, end_pos : Int32) : Array(Tuple(String, Int32))
      Noir::TopLevelSplit.split_spans(content, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, start_pos, end_pos)
    end

    private def quoted_literal(text : String) : String?
      trimmed = text.strip
      return if trimmed.size < 2
      first = trimmed[0]
      last = trimmed[-1]
      return unless (first == '\'' || first == '"' || first == '`') && first == last
      inner = trimmed[1..-2]
      return if inner.includes?('$') && first == '`' # template literal interpolation — not a static literal
      inner
    end
  end
end
