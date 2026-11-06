require "../../engines/javascript_engine"
require "../../../miniparsers/import_graph"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/ts_class_fields"
require "../../../miniparsers/ts_decorator_extractor"
require "../../../utils/top_level_split"

module Analyzer::Javascript
  class Nestjs < JavascriptEngine
    analyzer_for "js_nestjs"

    # Request-object fields read in handler bodies, paired with the param
    # type they map to. Iterated in this order when extracting params.
    REQUEST_OBJECT_FIELDS = { {"query", "query"}, {"body", "body"}, {"headers", "header"}, {"params", "path"} }

    private record GlobalPrefixExclude, path : String, method : String? = nil

    private record GlobalPrefixConfig, prefix : String, excludes : Array(GlobalPrefixExclude)

    # `app.enableVersioning({...})`: whether the version is a URL segment
    # (URI, the default) or read from the request (HEADER, MEDIA_TYPE,
    # CUSTOM), plus the raw `defaultVersion` and version-header expressions.
    # `defaults` is `defaultVersion` read as literal versions (what a
    # controller with no version of its own serves under URI versioning) and
    # `prefix` the URI segment's lead (`v` unless `prefix:` says otherwise).
    private record VersioningConfig, uri : Bool, default_version : String?, header : String?,
      defaults : Array(String) = [] of String, prefix : String = "v"

    # Name of the `route_conditions` entry that carries a route's raw version
    # list from the per-file scan to `separate_header_versions`.
    VERSION_CONDITION = "nest:version"

    # `(bootstrap file, config)` for every `enableVersioning` in the scan.
    # Read before the parallel scan: the type decides each route's URL.
    @nest_versioning = [] of Tuple(String, VersioningConfig)
    @nest_app_roots : Array(String)? = nil
    # Every file that starts an HTTP app (`NestFactory.create(...)`): within
    # one project root, each config belongs to the app nearest its file.
    @nest_bootstraps = [] of String
    # File => the URI version segments (`v1`) its routes were given, so a
    # `setGlobalPrefix` exclude can match the route without its version.
    @nest_version_segments = {} of String => Set(String)
    @nest_version_mutex = Mutex.new

    # Project-wide `EnumName.Member` / `Object.prop` -> value map, used to
    # resolve `@Controller(...)` prefix constants imported from another
    # file. nil until `analyze_with_extensions` seeds it.
    @nest_global_literals : Hash(String, Array(String))? = nil

    # DTO declarations, read lazily while routes are scanned: each file's
    # classes/interfaces, and every declared type name => the files
    # declaring it. Guarded by `@nest_dto_mutex` (lookups run in the scan's
    # fibers); the mutex only wraps cache reads and writes.
    @nest_decls_by_file = {} of String => Hash(String, Noir::TsClassFields::Decl)
    @nest_decl_index : Hash(String, Array(String))? = nil
    @nest_dto_mutex = Mutex.new

    # Extensions worth scanning for cross-file enum/object constants —
    # the enum may live in a `.ts` file even when the route-scan pass only
    # walks `.js`, so cast a wide net here.
    GLOBAL_LITERAL_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"]

    def analyze
      analyze_with_extensions([".js", ".jsx"])
    end

    # Scan every JS/TS source for `enum Foo { Bar = 'x' }` / `const Obj =
    # { k: 'v' } as const` definitions and keep only the DOTTED keys
    # (`Foo.Bar`, `Obj.k`) — those are the shape used cross-file as a
    # `@Controller`/`@Get` prefix. Bare-identifier consts are file-local
    # and collision-prone, so they stay per-file. Gated on the cheap
    # `enum `/`as const` substrings so most files are skipped outright.
    private def collect_global_literal_values : Hash(String, Array(String))
      acc = Hash(String, Array(String)).new
      all_files.each do |path|
        next unless GLOBAL_LITERAL_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        content = read_file_content(path)
        next unless content.includes?("enum ") || content.includes?("as const")
        extract_literal_values(content).each do |key, value|
          acc[key] = value if key.includes?(".") && !acc.has_key?(key)
        end
      rescue
        next
      end
      acc
    end

    NEST_BOOTSTRAP_CALL = /\bNestFactory\s*\.\s*create\s*[<(]/

    # Every `enableVersioning` in the scan, and (into `@nest_bootstraps`)
    # every file that bootstraps an HTTP app.
    private def collect_versioning_configs : Array(Tuple(String, VersioningConfig))
      configs = [] of Tuple(String, VersioningConfig)
      bootstraps = [] of String
      all_files.each do |path|
        next unless GLOBAL_LITERAL_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        next if ignored_nest_path?(path)
        content = read_file_content(path)
        versioning = content.includes?("enableVersioning")
        next unless versioning || content.includes?("NestFactory")
        code = Noir::JSRouteExtractor.strip_js_comments(content)
        bootstraps << path if code.matches?(NEST_BOOTSTRAP_CALL)
        next unless versioning
        literal_values = nil
        code.scan(/\.enableVersioning\s*\(/) do |match|
          open_paren = match.end(0) - 1
          next unless close_paren = Noir::JSRouteExtractor.find_matching_paren(code, open_paren)
          literal_values ||= file_literal_values(code)
          configs << {path, parse_versioning_options(code[(open_paren + 1)...close_paren], literal_values)}
        end
      rescue
        next
      end
      @nest_bootstraps = bootstraps.sort!
      configs.sort_by!(&.[0])
    end

    # `extract_literal_values` backed by the cross-file enum/object table.
    private def file_literal_values(code : String) : Hash(String, Array(String))
      values = extract_literal_values(code)
      @nest_global_literals.try &.each { |key, value| values[key] = value unless values.has_key?(key) }
      values
    end

    # `enableVersioning()` defaults to URI. A CUSTOM extractor's header is
    # the `headers[...]` key it reads.
    private def parse_versioning_options(args : String, literal_values : Hash(String, Array(String))) : VersioningConfig
      type = args.match(/\btype\s*:\s*VersioningType\.(\w+)/).try(&.[1]) || "URI"
      default_version = args.match(/\bdefaultVersion\s*:\s*(\[[^\]]*\]|[^,\n}]+)/).try(&.[1].strip)
      header = args.match(/\bheader\s*:\s*([^,\n}]+)/) || args.match(/\bheaders\s*\[\s*([^\]]+?)\s*\]/)
      VersioningConfig.new(type == "URI", default_version, header.try(&.[1].strip),
        default_version.try { |expr| literal_versions(expr, literal_values) } || [] of String, versioning_prefix(args))
    end

    # `defaultVersion: '1'` / `['1', '2']` / `VERSION_NEUTRAL` /
    # `API_VERSION` (a constant of the bootstrap's file or an imported enum
    # member): the literal versions. An identifier this scan cannot see the
    # value of is dropped rather than rendered as `v<IDENT>`.
    private def literal_versions(expr : String, literal_values : Hash(String, Array(String))) : Array(String)
      versions = [] of String
      expr.scan(/(['"`])([^'"`]+)\1|\b(VERSION_NEUTRAL|\d[\w.]*)\b|([A-Za-z_$][\w$.]*)/) do |match|
        values = match[4]? ? (literal_values[match[4]]? || [] of String) : [match[2]? || match[3]]
        values.each { |version| versions << version unless versions.includes?(version) }
      end
      versions
    end

    # `prefix: 'v'` (the default), `prefix: false` (bare version), or a
    # template whose interpolations are a deployment context path
    # (`${CONTEXT_PATH}v`): those resolve from the environment, empty unless
    # configured, so only the literal text is kept.
    private def versioning_prefix(args : String) : String
      match = args.match(/\bprefix\s*:\s*(false\b|(['"`])([^'"`]*)\2)/)
      return "v" unless match
      return "" if match[1] == "false"
      match[3].gsub(/\$\{[^}]*\}/, "")
    end

    # The `enableVersioning` governing `path`: the one of its app (see
    # `app_config_for`). Nil (no bootstrap seen, or another app's) keeps the
    # URI reading with no default version: one app's `defaultVersion` does
    # not move a sibling app's controllers.
    private def versioning_for(path : String) : VersioningConfig?
      app_config_for(path, @nest_versioning)
    end

    # The config of `entries` (`{file it was read from, config}`) that governs
    # `path`. Within `path`'s project root the anchors are the app bootstraps
    # and the config files; the ones sharing the most directories with `path`
    # are its app, and their config counts only when they agree on one. A
    # lone config outside every root governs the whole scan.
    private def app_config_for(path : String, entries : Array(Tuple(String, T))) : T? forall T
      return if entries.empty?
      roots = nest_app_roots
      root = nest_app_root_for(path, roots)
      anchors = (@nest_bootstraps + entries.map(&.[0])).uniq!.select { |anchor| nest_app_root_for(anchor, roots) == root }
      if anchors.empty?
        values = entries.map(&.[1]).uniq!
        return values.first if values.size == 1 && entries.all? { |(file, _)| nest_app_root_for(file, roots).empty? }
        return
      end
      best = anchors.max_of { |anchor| shared_dir_depth(anchor, path) }
      nearest = anchors.select { |anchor| shared_dir_depth(anchor, path) == best }
      found = entries.select { |(file, _)| nearest.includes?(file) }.map(&.[1]).uniq!
      found.size == 1 ? found.first : nil
    end

    # How many leading directories `a` and `b` share.
    private def shared_dir_depth(a : String, b : String) : Int32
      dirs_a = File.dirname(a).split('/')
      dirs_b = File.dirname(b).split('/')
      depth = 0
      while depth < dirs_a.size && depth < dirs_b.size && dirs_a[depth] == dirs_b[depth]
        depth += 1
      end
      depth
    end

    # Nest's own markers plus Nx application projects (`project.json` with
    # `"projectType": "application"`, often with no package.json of its own),
    # and each `-b` base when several are given.
    private def nest_app_roots : Array(String)
      @nest_app_roots ||= begin
        roots = discover_js_project_roots(app_root_markers, NEST_CONFIG_BASENAMES)
        all_files.each do |file|
          next unless File.basename(file) == "project.json"
          next unless read_file_content(file).matches?(/"projectType"\s*:\s*"application"/)
          add_project_root(roots, File.dirname(file))
        rescue
          next
        end
        if @normalized_base_paths.size > 1
          @normalized_base_paths.each { |(_, base)| roots << base unless roots.includes?(base) }
        end
        roots
      end
    end

    # Header-style versioning leaves the URL alone, so controllers of
    # different versions serve one address (`/v2/schedules` in
    # `SchedulesController_2024_04_15` and `_2024_06_11`). Unioned into one
    # row, the first file's handler would stand for both and the guards of
    # both would merge. The route an unversioned request reaches (no
    # version, VERSION_NEUTRAL, or one that includes `defaultVersion`) keeps
    # the plain row; every other version is kept apart by a route condition
    # and, when the header name resolves, a header param naming its version.
    private def separate_header_versions(result : Array(Endpoint))
      return unless result.any? { |endpoint| version_condition(endpoint) }

      constants : Hash(String, String)? = nil
      result.each_index.group_by { |idx| {result[idx].method, result[idx].url} }.each_value do |idxs|
        next unless idxs.any? { |idx| version_condition(result[idx]) }
        shared = idxs.map { |idx| result[idx].handler.try(&.name) }.uniq!.size > 1
        constants ||= project_constants if shared
        idxs.each do |idx|
          endpoint = result[idx]
          next unless condition = version_condition(endpoint)
          endpoint.route_conditions = [] of Param
          if shared && (table = constants)
            config = versioning_for(endpoint.details.code_paths.first?.try(&.path) || "")
            versions = condition.value.split(',').flat_map { |version| resolve_constant(version, table) }
            defaults = config.try(&.default_version).try { |expr| resolve_constant(expr, table).map(&.[0]) } || [] of String
            unless versions.any? { |(value, _)| value == "VERSION_NEUTRAL" || defaults.includes?(value) }
              endpoint.route_conditions = [Param.new(VERSION_CONDITION, versions.map(&.[0]).join(","), "header")]
              # A request sends one version; the first one this route serves.
              header = config.try(&.header).try { |expr| resolve_constant(expr, table).first? }
              endpoint.push_param(Param.new(header[0], versions.first[0], "header")) if header && header[1] && !versions.empty?
            end
          end
          result[idx] = endpoint
        end
      end
    end

    private def version_condition(endpoint : Endpoint) : Param?
      endpoint.route_conditions.find { |param| param.name == VERSION_CONDITION }
    end

    # Every `const NAME = <expr>` in the scan, first definition wins. Version
    # and header constants are usually imported (`@calcom/platform-constants`)
    # and re-cast (`VERSION_X as unknown as VersionValue`), so the per-file
    # literal table cannot see them.
    PROJECT_CONST_RE = /\bconst\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]+)?=\s*(\[[^\]]*\]|[^;\n]+)/

    private def project_constants : Hash(String, String)
      table = {} of String => String
      all_files.each do |path|
        next unless GLOBAL_LITERAL_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        content = read_file_content(path)
        next unless content.includes?("const ")
        content.scan(PROJECT_CONST_RE) { |match| table[match[1]] ||= match[2].strip }
      rescue
        next
      end
      table
    end

    # The values `expr` stands for, each with whether it reached a string
    # literal; an identifier that resolves no further stays as itself.
    private def resolve_constant(expr : String, table : Hash(String, String), depth : Int32 = 0) : Array(Tuple(String, Bool))
      # `VERSION_X as unknown as VersionValue` is VERSION_X.
      text = expr.strip.sub(/\A([A-Za-z_$][\w$.]*|(['"`])[^'"`]*\2)\s+as\s[\s\S]*\z/, "\\1")
      if literal = text.match(/\A(['"`])([^'"`]*)\1\z/)
        return [{literal[2], true}]
      end
      if text.starts_with?("[") && text.ends_with?("]")
        return split_top_level(text[1...-1], ',').reject(&.blank?).flat_map { |part| resolve_constant(part, table, depth + 1) }
      end
      bound = table[text]? if depth < 8
      bound ? resolve_constant(bound, table, depth + 1) : [{text, false}]
    end

    protected def analyze_with_extensions(extensions : Array(String)) : Array(Endpoint)
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      include_callee = callees_needed?
      # `(bootstrap file, config)` for every `setGlobalPrefix` in the scan,
      # not just the first one seen. Two NestJS apps under one scan base each
      # set their own prefix, and only the file they live beside tells them
      # apart.
      global_prefix_holder = [] of Tuple(String, GlobalPrefixConfig)
      global_prefix_mutex = Mutex.new

      # Resolve enum/object constants used cross-file as `@Controller(...)`
      # prefixes before the parallel scan so each file's per-file literal
      # table can fall back to them (immich mounts every asset/user/...
      # controller via `@Controller(RouteKey.User)` where `RouteKey` lives
      # in `src/enum.ts`). Built once, single-fiber, then read-only.
      @nest_global_literals = collect_global_literal_values
      @nest_versioning = collect_versioning_configs

      parallel_file_scan(extensions) do |path|
        next if ignored_nest_path?(path)
        analyze_nestjs_file(path, result, static_dirs, include_callee, global_prefix_holder, global_prefix_mutex)
      end

      separate_header_versions(result)

      # Process static directories to create endpoints for static files
      process_js_static_dirs(static_dirs, result)

      # `RouterModule.register([{ path, module }])` mounts a module's
      # controllers under `path`; the global prefix then goes on top of it.
      apply_router_module_prefixes(result)

      # Apply discovered global prefixes (`app.setGlobalPrefix('api')`)
      # — the bootstrap call mounts every controller under that prefix.
      apply_global_prefixes(result, global_prefix_holder)

      result
    end

    ROUTER_REGISTER_CALL = /\bRouterModule\s*\.\s*register\s*\(/
    MODULE_DECORATOR     = /@Module\s*\(/
    MODULE_CLASS         = /\bclass\s+(\w+)/

    # Prefix the controllers of every module `RouterModule.register` mounts.
    # A controller is identified by (declaring file, class name): two
    # controllers may share a class name in different modules (hedgedoc's
    # private and public `NotesController`). Only the module's own
    # `controllers` array is prefixed, as in Nest; `children` nest paths.
    private def apply_router_module_prefixes(result : Array(Endpoint))
      mounts = [] of Tuple(String, String)
      files = all_files.select { |path| GLOBAL_LITERAL_EXTENSIONS.any? { |ext| path.ends_with?(ext) } && !ignored_nest_path?(path) }
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("RouterModule")
        code = Noir::JSRouteExtractor.strip_js_comments(content)
        code.scan(ROUTER_REGISTER_CALL) do |match|
          open_paren = match.end(0) - 1
          close_paren = Noir::JSRouteExtractor.find_matching_paren(code, open_paren) || next
          arg = code[(open_paren + 1)...close_paren].strip
          arg = routes_array_for(arg, path, code) || next if arg.matches?(/\A[A-Za-z_$][\w$]*\z/)
          collect_router_mounts(arg, "", path, file_literal_values(code), mounts, 0)
        end
      rescue
        next
      end
      return if mounts.empty?

      prefix_by_controller = {} of Tuple(String, String) => String
      mounts.each do |(module_name, prefix)|
        module_controllers(module_name, files).each do |key|
          prefix_by_controller[key] ||= prefix
        end
      end
      return if prefix_by_controller.empty?

      result.each_with_index do |endpoint, idx|
        handler = endpoint.handler || next
        file = Noir::PathScope.expand(handler.path || next)
        klass = handler.name.partition('.')[0]
        prefix = prefix_by_controller[{file, klass}]? || next
        endpoint.url = join_router_prefix(prefix, endpoint.url)
        result[idx] = endpoint
      end
    end

    # `[{ path, module, children: [...] }, ...]` into (module, full path).
    private def collect_router_mounts(text : String, parent : String, file : String,
                                      literals : Hash(String, Array(String)),
                                      mounts : Array(Tuple(String, String)), depth : Int32)
      return if depth > 6 || !text.starts_with?("[") || !text.ends_with?("]")
      split_top_level(text[1...-1], ',').each do |element|
        element = element.strip
        next unless element.starts_with?("{") && element.ends_with?("}")
        path_expr = module_name = children = nil
        split_top_level(element[1...-1], ',').each do |prop|
          key, _, value = prop.partition(':')
          case key.strip
          when "path"     then path_expr = value.strip
          when "module"   then module_name = value.strip
          when "children" then children = value.strip
          end
        end
        path = (expr = path_expr) ? router_path_literal(expr, file, literals) : ""
        next if path.nil?
        full = join_router_prefix(parent, path)
        if (name = module_name) && name.matches?(/\A\w+\z/)
          mounts << {name, full}
        end
        if kids = children
          collect_router_mounts(kids, full, file, literals, mounts, depth + 1)
        end
      end
    end

    # `const routes: Routes = [...]` behind `RouterModule.register(routes)`,
    # declared in this file.
    private def routes_array_for(name : String, file : String, code : String) : String?
      decl = code.match(/\b(?:const|let|var)\s+#{Regex.escape(name)}\s*(?::[^=\n]+)?=\s*\[/) || return
      open = decl.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_bracket(code, open) || return
      code[open..close]
    end

    private def router_path_literal(expr : String, file : String, literals : Hash(String, Array(String))) : String?
      if lit = expr.match(/\A(['"`])([^'"`$]*)\1\z/)
        return lit[2]
      end
      return unless expr.matches?(/\A[\w$.]+\z/)
      if value = literals[expr]?.try(&.first?)
        return value
      end
      read_file_content(file).scan(NAMED_IMPORT) do |imp|
        declared = imported_name(imp[1], expr) || next
        next unless imp[2].starts_with?('.')
        target = Noir::ImportGraph.resolve_relative_import(file, imp[2], boundary: import_boundary_for(file)) || next
        return extract_literal_values(read_file_content(target))[declared]?.try(&.first?)
      end
      nil
    end

    private def join_router_prefix(prefix : String, url : String) : String
      base = prefix.empty? ? "" : "/#{prefix.strip('/')}"
      base = "" if base == "/"
      rest = url == "/" ? "" : (url.starts_with?("/") ? url : "/#{url}")
      joined = "#{base}#{rest}"
      joined.empty? ? "/" : joined
    end

    # (file, class) of every controller in the `controllers` array of the
    # `@Module` class named `module_name`.
    private def module_controllers(module_name : String, files : Array(String)) : Array(Tuple(String, String))
      found = [] of Tuple(String, String)
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("@Module")
        code = Noir::JSRouteExtractor.strip_js_comments(content)
        code.scan(MODULE_DECORATOR) do |match|
          open_paren = match.end(0) - 1
          close_paren = Noir::JSRouteExtractor.find_matching_paren(code, open_paren) || next
          klass = code[(close_paren + 1)..].match(MODULE_CLASS) || next
          next unless klass[1] == module_name
          list = code[open_paren...close_paren].match(/\bcontrollers\s*:\s*\[([^\]]*)\]/) || next
          list[1].split(',').each do |raw|
            name = raw.strip
            next unless name.matches?(/\A\w+\z/)
            found << {Noir::PathScope.expand(controller_file(name, path, code)), name}
          end
        end
      rescue
        next
      end
      found
    end

    # The file declaring controller `name` as seen from the module file.
    private def controller_file(name : String, module_file : String, code : String) : String
      code.scan(NAMED_IMPORT) do |imp|
        imported_name(imp[1], name) || next
        next unless imp[2].starts_with?('.')
        target = Noir::ImportGraph.resolve_relative_import(module_file, imp[2], boundary: import_boundary_for(module_file)) || next
        return target
      end
      module_file
    end

    protected def strip_trailing_slashes(endpoints : Array(Endpoint)) : Array(Endpoint)
      endpoints.map do |endpoint|
        endpoint.url = endpoint.url.rstrip('/') if endpoint.url.size > 1
        endpoint
      end
    end

    private def ignored_nest_path?(path : String) : Bool
      # Scan-base-relative, never absolute: a `__tests__/` or `test/`
      # directory ABOVE the scan base is not this project's test tree.
      relative = base_relative_path(path)
      # `app.e2e-spec.ts` is the Nest CLI's e2e suite name.
      relative.includes?(".test.") || relative.includes?(".spec.") || relative.includes?(".e2e-spec.") ||
        relative.includes?("/__tests__/") || relative.includes?("/__mocks__/") ||
        relative.includes?("/test/fixtures/") || relative.includes?("/tests/fixtures/")
    end

    # Markers that identify a NestJS application root, so a prefix set in
    # one app's bootstrap is not stamped onto another app's controllers.
    NEST_PACKAGE_MARKERS  = ["@nestjs/core", "@nestjs/common"]
    NEST_CONFIG_BASENAMES = ["nest-cli.json"]

    protected def app_root_markers : Array(String)
      NEST_PACKAGE_MARKERS
    end

    # Route each discovered `setGlobalPrefix` to the endpoints it actually
    # governs.
    #
    # This used to be `apply_global_prefix(result, holder.first?)` over a
    # holder that kept only the first prefix found anywhere in the scan. Two
    # NestJS apps under one scan base — an ordinary monorepo — therefore had
    # one app's prefix stamped on both: `appB` with `setGlobalPrefix('internal')`
    # was reported at `/apiv1/appB/ping` because `appA` happened to be read
    # first. The URL reported did not exist and the real one was missing, so
    # anything consuming the output (a DAST target list, an OAS export,
    # `--probe`) was aimed at a 404. Worse, "first" was decided by which
    # `parallel_file_scan` fiber finished first, so the same input could
    # report different URLs between runs.
    private def apply_global_prefixes(result : Array(Endpoint),
                                      entries : Array(Tuple(String, GlobalPrefixConfig)))
      return if entries.empty?

      # Sort before anything picks a winner: the collection order is fiber
      # completion order, which is not stable across runs.
      sorted = entries.sort_by { |(path, _)| path }
      roots = nest_app_roots

      by_root = {} of String => GlobalPrefixConfig
      sorted.each do |(path, config)|
        root = nest_app_root_for(path, roots)
        by_root[root] = config unless by_root.has_key?(root)
      end

      # One app (the overwhelmingly common case, and every project without a
      # discoverable root) keeps the original whole-scan behaviour, including
      # for endpoints that carry no source file such as static-directory ones.
      # A single config inside one of several discovered apps is not that
      # case: it governs its own app only, not the apps that set no prefix.
      # A second app bootstrapped beside it (an Nx or plain `apps/*` layout
      # under one package.json) is not that case either.
      config_files = sorted.map(&.[0])
      if by_root.size <= 1 && (roots.size <= 1 || by_root.has_key?("")) &&
         @nest_bootstraps.all? { |file| config_files.includes?(file) }
        apply_global_prefix(result, sorted.first[1])
        return
      end

      result.each_with_index do |endpoint, idx|
        file = endpoint.details.code_paths.first?.try(&.path)
        next if file.nil?
        config = app_config_for(file, sorted)
        next if config.nil?
        prefixed = prefix_endpoint(endpoint, config)
        result[idx] = prefixed if prefixed
      end
    end

    # The deepest discovered project root containing `path`, or `""` when the
    # scan found no root for it. Deepest, not first: a nested app inside a
    # workspace root must win over the workspace.
    private def nest_app_root_for(path : String, roots : Array(String)) : String
      expanded = Noir::PathScope.expand(path)
      best = ""
      roots.each do |root|
        next unless Noir::PathScope.under_normalized_root?(expanded, root)
        best = root if root.size > best.size
      end
      best
    end

    # Prepend the discovered `app.setGlobalPrefix('api')` value to
    # every endpoint URL. Endpoints whose URL already starts with the
    # normalized prefix (e.g. controllers that hard-coded `/api/...`)
    # are left untouched so we don't double-prefix.
    private def apply_global_prefix(result : Array(Endpoint), config : GlobalPrefixConfig?)
      return unless config

      # `Endpoint` is a struct (value type), so the block-local
      # binding is a copy — write back through the index to make the
      # URL change visible to callers.
      result.each_with_index do |endpoint, idx|
        prefixed = prefix_endpoint(endpoint, config)
        result[idx] = prefixed if prefixed
      end
    end

    # The prefixed endpoint, or `nil` when this config leaves it alone.
    # Shared by the single-app and per-app paths so the two cannot drift.
    private def prefix_endpoint(endpoint : Endpoint, config : GlobalPrefixConfig) : Endpoint?
      normalized = normalized_global_prefix(config)
      return if normalized.nil?
      return if global_prefix_excluded?(endpoint, config.excludes)
      # Controllers that hard-coded `/api/...` are already where the prefix
      # would put them; prefixing again would double it.
      return if endpoint.url.starts_with?(normalized + "/") || endpoint.url == normalized

      # A root `@Get()` is served at the bare prefix: `/api`, not `/api/`.
      endpoint.url = if endpoint.url == "/"
                       normalized
                     elsif endpoint.url.starts_with?("/")
                       "#{normalized}#{endpoint.url}"
                     else
                       "#{normalized}/#{endpoint.url}"
                     end
      endpoint
    end

    private def normalized_global_prefix(config : GlobalPrefixConfig) : String?
      prefix = config.prefix
      return if prefix.empty?

      normalized = prefix.starts_with?("/") ? prefix : "/#{prefix}"
      normalized = normalized.chomp("/")
      normalized.empty? ? nil : normalized
    end

    # Nest matches an exclude against the route without its URI version:
    # `exclude: ['health']` keeps `/v1/health` out of the prefix.
    private def global_prefix_excluded?(endpoint : Endpoint, excludes : Array(GlobalPrefixExclude)) : Bool
      urls = [endpoint.url]
      file = endpoint.details.code_paths.first?.try(&.path)
      segments = file && @nest_version_mutex.synchronize { @nest_version_segments[file]? }
      if segments
        segments.each do |segment|
          # Routes are still relative here (`v1/health`).
          url = endpoint.url.lchop('/')
          urls << (url[segment.size..].presence || "/") if url == segment || url.starts_with?("#{segment}/")
        end
      end
      excludes.any? do |exclude|
        next false if exclude.method && exclude.method != "ALL" && exclude.method != endpoint.method
        urls.any? { |url| exclude_path_matches?(url, exclude.path) }
      end
    end

    private def exclude_path_matches?(url : String, exclude_path : String) : Bool
      normalized_url = normalize_path_for_prefix_exclude(url)
      normalized_exclude = normalize_path_for_prefix_exclude(exclude_path)

      if normalized_exclude.ends_with?("*")
        normalized_url.starts_with?(normalized_exclude.rstrip('*'))
      else
        normalized_url == normalized_exclude
      end
    end

    private def normalize_path_for_prefix_exclude(path : String) : String
      normalized = path.strip
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized.squeeze('/')
      normalized = normalized.chomp("/") unless normalized == "/"
      normalized
    end

    # Midway imports the same `@Controller`/`@Get` vocabulary from
    # `@midwayjs/*`. `Analyzer::Typescript::Midway` claims those `.ts` files
    # and `Analyzer::Typescript::Nestjs` leaves them to it; JavaScript stays
    # with this analyzer, as there is no JS Midway analyzer.
    MIDWAY_IMPORT = "@midwayjs/"

    protected def owns_source?(content : String) : Bool
      true
    end

    # Whether a file this analyzer does not own may still set the prefix
    # (`extract_global_prefix_config`); a framework whose prefix is fixed
    # skips every unowned file before stripping its comments.
    protected def prefix_outside_owned_sources? : Bool
      true
    end

    # Class decorators that open a controller and carry its path prefix.
    # The other decorator-controller frameworks
    # (`Analyzer::Typescript::DecoratorController`) name their own.
    CONTROLLER_DECORATORS = ["Controller"]

    protected def controller_decorators : Array(String)
      CONTROLLER_DECORATORS
    end

    ROUTE_DECORATOR_METHODS = {
      "Get"         => ["GET"],
      "Post"        => ["POST"],
      "Put"         => ["PUT"],
      "Delete"      => ["DELETE"],
      "Del"         => ["DELETE"], # Midway's spelling
      "Patch"       => ["PATCH"],
      "Options"     => ["OPTIONS"],
      "Head"        => ["HEAD"],
      "QueryMethod" => ["QUERY"],
      # `@Sse` opens a Server-Sent Events stream — HTTP GET under
      # the hood, so it counts as a real route.
      "Sse" => ["GET"],
      "All" => ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"],
    }

    # Method decorator name => verbs.
    protected def route_decorator_methods : Hash(String, Array(String))
      ROUTE_DECORATOR_METHODS
    end

    private def analyze_nestjs_file(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)), include_callee : Bool, global_prefix_holder : Array(Tuple(String, GlobalPrefixConfig)), global_prefix_mutex : Mutex)
      content = read_file_content(path)
      owned = owns_source?(content)
      return unless owned || prefix_outside_owned_sources?

      # Strip JS/TS comments so commented-out decorators
      # (e.g. `// @Get('/old')`) don't generate phantom routes.
      sanitized = Noir::JSRouteExtractor.strip_js_comments(content)

      # `app.setGlobalPrefix('api')` in a bootstrap file scopes
      # every controller below it. Record it now; apply once after
      # all files have been parsed. Read before the ownership gate: a
      # Midway config file need not import `@midwayjs/*`.
      if prefix = extract_global_prefix_config(sanitized, path)
        global_prefix_mutex.synchronize do
          global_prefix_holder << {path, prefix}
          nil # Crystal 1.20 can't infer the `<<` result type here
        end
      end

      return unless owned

      collect_static_paths(path, content, static_dirs, :nestjs)
      collect_static_paths(path, content, static_dirs, :express) if nestjs_bootstrap_source?(content)

      analyze_nestjs_controllers(sanitized, path, result, include_callee)
    rescue e : Exception
      logger.debug "Error analyzing NestJS file #{path}: #{e.message}"
    end

    # Precompiled once — a single PCRE2-JIT scan replaces five naive
    # String#includes? substring scans over the whole file content.
    # Regex.union auto-escapes each literal, so this is provably
    # equivalent to the OR-of-includes? it replaces.
    NESTJS_BOOTSTRAP_RE = Regex.union(
      "NestFactory.create",
      "from '@nestjs/core'", "from \"@nestjs/core\"",
      "require('@nestjs/core')", "require(\"@nestjs/core\")"
    )

    private def nestjs_bootstrap_source?(content : String) : Bool
      content.matches?(NESTJS_BOOTSTRAP_RE)
    end

    # Detect `app.setGlobalPrefix('api', { exclude: [...] })`.
    # Dynamic expressions are ignored conservatively — false-positive
    # prefixing would mis-route every controller. An `exclude` array may be
    # a named const (see `exclude_array_source`).
    private def extract_global_prefix_config(content : String, path : String) : GlobalPrefixConfig?
      literal_values = extract_literal_values(content)

      content.scan(/\.setGlobalPrefix\s*\(/) do |match|
        open_paren = (match.end(0) || 0) - 1
        next if open_paren < 0

        close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
        next unless close_paren

        args = split_top_level(content[(open_paren + 1)...close_paren], ',')
        next if args.empty?

        prefixes = literal_paths_from_expression(args[0], literal_values)
        next if prefixes.nil?
        next if prefixes.size != 1 || prefixes[0].empty?

        excludes = args.size > 1 ? extract_global_prefix_excludes(args[1], literal_values, content, path) : [] of GlobalPrefixExclude
        return GlobalPrefixConfig.new(prefixes[0], excludes)
      end
      nil
    end

    private def extract_global_prefix_excludes(options : String, literal_values : Hash(String, Array(String)), content : String, path : String) : Array(GlobalPrefixExclude)
      excludes = [] of GlobalPrefixExclude
      match = options.match(/\bexclude\s*:\s*/)
      return excludes unless match

      # `exclude: [...]` inline, or `exclude: excludePaths` naming an array
      # const in this file or imported from another one (immich).
      array = options[match.end(0)..]
      unless array.starts_with?('[')
        name = array.match(/\A[A-Za-z_$][\w$]*/).try(&.[0])
        array = name && exclude_array_source(name, content, path)
        return excludes unless array
      end

      close = find_matching_bracket(array, 0)
      return excludes unless close

      split_top_level(array[1...close], ',').each do |entry|
        excludes.concat(parse_global_prefix_exclude_entry(entry, literal_values))
      end
      excludes
    end

    # The `[...]` bound to `const name = [...]` in `content`, else in the
    # file `content` imports `name` from. Relative specifiers resolve through
    # `ImportGraph`; a path-alias one (`src/constants.js` under a tsconfig
    # `baseUrl`) names the file by its tail, and the scanned file sharing
    # the longest directory prefix with `path` wins.
    private def exclude_array_source(name : String, content : String, path : String) : String?
      esc = Regex.escape(name)
      if source = array_const_source(content, esc)
        return source
      end

      spec = content.match(/\bimport\s*(?:type\s+)?\{[^}]*\b#{esc}\b[^}]*\}\s*from\s*['"]([^'"]+)['"]/).try(&.[1])
      return unless spec

      target = if spec.starts_with?(".")
                 Noir::ImportGraph.resolve_relative_import(path, spec, boundary: import_boundary_for(path))
               else
                 stem = "/" + spec.sub(JS_SOURCE_EXT_RE, "")
                 all_files.select { |file| file.sub(JS_SOURCE_EXT_RE, "").ends_with?(stem) }
                   .max_by? { |file| common_prefix_size(file, path) }
               end
      return unless target

      array_const_source(Noir::JSRouteExtractor.strip_js_comments(read_file_content(target)), esc)
    end

    JS_SOURCE_EXT_RE = /\.[cm]?[jt]sx?$/

    private def array_const_source(content : String, escaped_name : String) : String?
      match = content.match(/\b(?:const|let|var)\s+#{escaped_name}\s*(?::[^=]+)?=\s*\[/)
      return unless match
      open = match.end(0) - 1
      close = find_matching_bracket(content, open)
      content[open..close] if close
    end

    private def common_prefix_size(a : String, b : String) : Int32
      size = 0
      while size < a.bytesize && size < b.bytesize && a.byte_at(size) == b.byte_at(size)
        size += 1
      end
      size
    end

    private def parse_global_prefix_exclude_entry(entry : String, literal_values : Hash(String, Array(String))) : Array(GlobalPrefixExclude)
      stripped = entry.strip
      return [] of GlobalPrefixExclude if stripped.empty?

      paths = [] of String
      method : String? = nil

      if stripped.starts_with?("{")
        if path_match = stripped.match(/(?:^|[,{]\s*)path\s*:\s*([\s\S]*?)(?:,\s*\w+\s*:|\}\s*$)/m)
          paths = literal_paths_from_expression(path_match[1].strip, literal_values) || [] of String
        end

        if method_match = stripped.match(/\bmethod\s*:\s*(?:RequestMethod\.)?([A-Za-z]+)/)
          method = method_match[1].upcase
        end
      else
        paths = literal_paths_from_expression(stripped, literal_values) || [] of String
      end

      paths.map { |path| GlobalPrefixExclude.new(path, method) }
    end

    private def find_matching_bracket(text : String, open_idx : Int32) : Int32?
      depth = 0
      quote : Char? = nil
      escaped = false

      text.each_char_with_index do |char, idx|
        next if idx < open_idx

        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '['
          depth += 1
        when ']'
          depth -= 1
          return idx if depth == 0
        end
      end

      nil
    end

    # Any of the framework's class decorators in the file: the cheap gate
    # before it is parsed.
    private def controller_source?(content : String) : Bool
      controller_decorators.any? { |name| content.includes?("@#{name}") }
    end

    private def analyze_nestjs_controllers(content : String, path : String, result : Array(Endpoint), include_callee : Bool)
      return unless controller_source?(content)
      literal_values = extract_literal_values(content)
      # Back-fill cross-file enum/object constants (per-file definitions
      # already in `literal_values` win — they are the more specific source).
      if global = @nest_global_literals
        global.each { |key, value| literal_values[key] = value unless literal_values.has_key?(key) }
      end
      # URI versioning (Nest's default, and the reading when no
      # `enableVersioning` is in the scan) prepends `v<n>`:
      # `@Controller({ path: 'cats', version: '1' })` serves `/v1/cats`.
      # HEADER, MEDIA_TYPE and CUSTOM versioning leave the URL untouched.
      versioning = versioning_for(path)
      uri_versioning = versioning.try(&.uri) != false

      Noir::TsDecoratorExtractor.extract(content, path).each do |klass|
        controller = klass.decorators.find { |decorator| decorator.called && controller_decorators.includes?(decorator.name) } || next
        base_paths = controller_base_paths(controller.args.first? || "", literal_values, controller.name)
        versions = controller.name == "Controller" ? controller_versions(controller.args.first?) : [] of String
        process_http_methods(content, klass, base_paths, versions, uri_versioning, versioning, path, result, include_callee, literal_values, controller.name)
      end
    end

    # Combine the controller's base paths with each version into a
    # set of `v<version>/<base>` paths. `'VERSION_NEUTRAL'` (Nest's
    # sentinel) is rendered as no prefix.
    private def expand_versions(base_paths : Array(String), versions : Array(String), literal_values : Hash(String, Array(String)), version_prefix : String = "v") : Array(String)
      expanded = [] of String
      versions.each do |v|
        prefix = v == "VERSION_NEUTRAL" ? "" : "#{version_prefix}#{literal_values[v]?.try(&.first?) || v}"
        base_paths.each do |bp|
          if prefix.empty?
            expanded << bp
          elsif bp.empty?
            expanded << prefix
          else
            normalized = bp.starts_with?("/") ? bp[1..] : bp
            expanded << "#{prefix}/#{normalized}"
          end
        end
      end
      expanded.uniq
    end

    # The versions in `@Controller({ ..., version: ... })`'s options:
    #   version: '1'                 -> ["1"]
    #   version: 1                   -> ["1"]
    #   version: ['1', '2']          -> ["1", "2"]
    #   version: VERSION_NEUTRAL     -> ["VERSION_NEUTRAL"]
    # None (no `version:` key) leaves the route URL untouched.
    private def controller_versions(arg : String?) : Array(String)
      inner = arg.try(&.strip) || return [] of String
      return [] of String unless inner.starts_with?("{")

      versions = [] of String

      # version: ['1', '2'] or [VERSION_A, VERSION_NEUTRAL]
      if am = inner.match(/\bversion\s*:\s*\[([^\]]+)\]/)
        am[1].scan(/['"]([^'"]+)['"]|([A-Za-z_][\w.]*|\d+)/) do |m|
          version = m[1]? || m[2]
          versions << version unless versions.includes?(version)
        end
        return versions unless versions.empty?
      end

      # version: '1' or version: "1"
      if sm = inner.match(/\bversion\s*:\s*['"]([^'"]+)['"]/)
        versions << sm[1]
        return versions
      end

      # version: 1 (numeric literal) or version: VERSION_NEUTRAL (identifier)
      if im = inner.match(/\bversion\s*:\s*([A-Za-z_][\w.]*|\d+)/)
        versions << im[1]
      end

      versions
    end

    # The base paths a class decorator's first argument scopes its routes
    # under. Recognized shapes:
    #
    #   @Controller()                              -> [""]
    #   @Controller('users')                       -> ["users"]
    #   @Controller(['users', 'admins'])           -> ["users", "admins"]
    #   @Controller({ path: 'users' })             -> ["users"]
    #   @Controller({ path: API.USERS })           -> ["users"]
    #   @Controller(SOME_CONST)                    -> [""]  (best-effort
    #     fallback: register the controller without a prefix rather
    #     than miss every route inside it.)
    #
    # Midway takes an options object after the path —
    # `@Controller('/api', { middleware })` — so only the first argument is
    # the path.
    private def controller_base_paths(arg : String, literal_values : Hash(String, Array(String)), name : String) : Array(String)
      literal_paths_from_expression(arg, literal_values) || [""]
    end

    private def extract_literal_values(content : String) : Hash(String, Array(String))
      literal_values = Hash(String, Array(String)).new

      content.scan(/\b(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(['"`])([^'"`]*?)\2/) do |match|
        next unless match.size >= 4
        literal_values[match[1]] = [match[3]]
      end

      content.scan(/\benum\s+(\w+)\s*\{([\s\S]*?)\}/m) do |match|
        next unless match.size >= 3
        enum_name = match[1]
        body = match[2]
        body.scan(/(\w+)\s*=\s*(['"`])([^'"`]*?)\2/) do |member|
          next unless member.size >= 4
          literal_values["#{enum_name}.#{member[1]}"] = [member[3]]
        end
      end

      content.scan(/\b(?:export\s+)?const\s+(\w+)\s*=\s*\{([\s\S]*?)\}\s*(?:as\s+const)?/m) do |match|
        next unless match.size >= 3
        object_name = match[1]
        body = match[2]
        body.scan(/(?:['"`]?(\w+)['"`]?)\s*:\s*(['"`])([^'"`]*?)\2/) do |property|
          next unless property.size >= 4
          literal_values["#{object_name}.#{property[1]}"] = [property[3]]
        end
      end

      literal_values
    end

    private def literal_paths_from_expression(expression : String, literal_values : Hash(String, Array(String))) : Array(String)?
      # A last object key keeps its trailing comma: `{ path: "/v2/x", }`.
      expr = expression.strip.chomp(',').strip
      return [""] if expr.empty?

      expr = expr.sub(/\s+as\s+const\s*$/, "").strip

      if str = expr.match(/^(['"`])([^'"`]*)\1$/)
        return [str[2]]
      end

      if expr.starts_with?("[") && expr.ends_with?("]")
        paths = [] of String
        split_top_level(expr[1...-1], ',').each do |part|
          resolved = literal_paths_from_expression(part, literal_values)
          resolved.try { |values| paths.concat(values) }
        end
        return paths unless paths.empty?
        return
      end

      if expr.starts_with?("{")
        if path_match = expr.match(/(?:^|[,{]\s*)path\s*:\s*([\s\S]*?)(?:,\s*\w+\s*:|\}\s*$)/m)
          path_expr = path_match[1].strip
          path_expr = path_expr[0...-1].strip if path_expr.ends_with?("}")
          return literal_paths_from_expression(path_expr, literal_values)
        end
        return
      end

      plus_parts = split_top_level(expr, '+')
      if plus_parts.size > 1
        pieces = [] of String
        plus_parts.each do |part|
          values = literal_paths_from_expression(part, literal_values)
          return unless values && values.size == 1
          pieces << values[0]
        end
        return [pieces.join]
      end

      literal_values[expr]?
    end

    private def split_top_level(text : String, delimiter : Char) : Array(String)
      Noir::TopLevelSplit.split(text, delimiter, Noir::TopLevelSplit::Rules::JS)
    end

    private def process_http_methods(content : String, klass : Noir::TsDecoratorExtractor::ClassDecl, base_paths : Array(String), controller_versions : Array(String), uri_versioning : Bool, versioning : VersioningConfig?, file_path : String, result : Array(Endpoint), include_callee : Bool, literal_values : Hash(String, Array(String)), controller_decorator : String)
      method_map = route_decorator_methods

      klass.methods.each do |method|
        routes = method.decorators.select { |decorator| decorator.called && method_map.has_key?(decorator.name) }
        next if routes.empty?

        decorator_block = method.decorators.join("\n", &.text)
        # A member's `@Version` overrides, rather than stacks on, the
        # controller's.
        versions = method_versions(method.decorators)
        versions = controller_versions if versions.empty?
        # Under URI versioning a route with no version of its own serves
        # `defaultVersion` (`/v1/auth/login` for `@Controller('auth')`).
        effective_versions = versions.empty? && uri_versioning && versioning ? versioning.defaults : versions
        version_prefix = versioning.try(&.prefix) || "v"
        effective_base_paths = uri_versioning && !effective_versions.empty? ? expand_versions(base_paths, effective_versions, literal_values, version_prefix) : base_paths

        body = method_body(content, method)
        # Once per method: every version × path × verb endpoint shares them.
        callees = nil
        dto_fields = dto_params(method.params, file_path)
        # `export default class { ... }` has no name to qualify the method with.
        handler_name = klass.name.empty? ? method.name : "#{klass.name}.#{method.name}"
        handler = Handler.new(handler_name, file_path, method.row + 1)

        routes.each do |route|
          route_paths = literal_paths_from_expression(route.args.first? || "", literal_values) || next
          record_version_segments(file_path, effective_versions, literal_values, version_prefix) if uri_versioning
          if include_callee && body && callees.nil?
            callees = Noir::JSCalleeExtractor.callees_for_function_body(body, file_path, method.body_row + 1)
          end
          decorator_line = route.row + 1
          methods = method_map[route.name]

          effective_base_paths.each do |base_path|
            route_paths.each do |route_path|
              full_path = combine_paths(base_path, route_path)
              methods.each do |verb|
                endpoint = Endpoint.new(full_path, verb)
                endpoint.details = Details.new(PathInfo.new(file_path, decorator_line))
                endpoint.handler = handler
                endpoint.route_conditions = [Param.new(VERSION_CONDITION, versions.join(","), "header")] unless uri_versioning || versions.empty?

                extract_path_parameters(full_path, endpoint)
                extract_decorator_parameters(method.params, endpoint, dto_fields)
                extract_interceptor_parameters(decorator_block, endpoint)
                route_decorated(endpoint, method, route, controller_decorator)
                extract_request_object_params(body, method.params, endpoint)
                callees.try &.each do |name, callee_path, line|
                  endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
                end

                result << endpoint
              end
            end
          end
        end
      end
    end

    private def record_version_segments(file_path : String, versions : Array(String), literal_values : Hash(String, Array(String)), version_prefix : String)
      segments = versions.compact_map do |version|
        "#{version_prefix}#{literal_values[version]?.try(&.first?) || version}" unless version == "VERSION_NEUTRAL"
      end
      return if segments.empty?
      @nest_version_mutex.synchronize do
        set = @nest_version_segments[file_path] ||= Set(String).new
        segments.each { |segment| set << segment }
      end
    end

    # `@Version('2')`, `@Version(['1', '2'])`, `@Version(V2)`.
    private def method_versions(decorators : Array(Noir::TsDecoratorExtractor::Decorator)) : Array(String)
      versions = [] of String
      decorators.each do |decorator|
        next unless decorator.called && decorator.name == "Version"
        expr = decorator.args.first?.try(&.strip) || next
        if expr.starts_with?("[") && expr.ends_with?("]")
          expr.scan(/['"]([^'"]+)['"]|([A-Za-z_][\w.]*|\d+)/) do |m|
            version = m[1]? || m[2]
            versions << version unless versions.includes?(version)
          end
        elsif sm = expr.match(/^['"]([^'"]+)['"]$/)
          versions << sm[1] unless versions.includes?(sm[1])
        elsif im = expr.match(/^([A-Za-z_][\w.]*|\d+)$/)
          versions << im[1] unless versions.includes?(im[1])
        end
      end
      versions
    end

    # The text inside a method's braces.
    private def method_body(content : String, method : Noir::TsDecoratorExtractor::Method) : String?
      start = method.body_start || return
      stop = method.body_end || return
      content.byte_slice(start, stop - start) if stop >= start
    end

    STRING_ARG = /\A(['"`])([^'"`]+)\1\z/

    # The value of a decorator argument that is one plain string literal.
    private def string_arg(arg : String?) : String?
      arg.try(&.strip.match(STRING_ARG)).try(&.[2])
    end

    # Whether an argument decorator counts: NestJS's are factories, so only
    # a called one (`@Body()`, never a bare `@Body`).
    private def param_decorator?(decorator : Noir::TsDecoratorExtractor::Decorator) : Bool
      decorator.called
    end

    # NestJS's argument decorators in the order their params are added: the
    # decorator, the param type, and the param one without a string argument
    # stands for (nil: none). `@Query('q')` is the query param `q`;
    # `@Query()` / `@Query(pipe)` the whole query.
    NEST_PARAM_DECORATORS = [
      {"Query", "query", "query"},
      {"Param", "path", nil},
      {"Body", "body", "body"},
      {"Headers", "header", "headers"},
      # `@HostParam('account')` — subdomain capture when the controller
      # uses `@Controller({ host: ':account.example.com' })`.
      {"HostParam", "path", nil},
      # `@UploadedFile('field')` / `@UploadedFiles()` — multer integration.
      {"UploadedFile", "body", "file"},
      {"UploadedFiles", "body", "files"},
    ] of Tuple(String, String, String?)

    private def extract_decorator_parameters(params : Array(Noir::TsDecoratorExtractor::Parameter), endpoint : Endpoint,
                                             dto_fields : Hash(String, Array(String)) = {} of String => Array(String))
      # A whole-object `@Query()` / `@Body()` typed with a DTO is the DTO's
      # fields; one whose type does not resolve stays a single generic param.
      dto_fields.each do |param_type, names|
        names.each { |name| endpoint.push_param(Param.new(name, "", param_type)) }
      end

      NEST_PARAM_DECORATORS.each do |decorator_name, param_type, whole_name|
        whole = false
        params.each do |param|
          param.decorators.each do |decorator|
            next unless decorator.called && decorator.name == decorator_name
            if name = string_arg(decorator.args.first?)
              endpoint.push_param(Param.new(name, "", param_type))
            else
              whole = true
            end
          end
        end
        next unless whole && whole_name
        next if DTO_PARAM_TYPES.has_key?(decorator_name) && dto_fields.has_key?(param_type)
        endpoint.push_param(Param.new(whole_name, "", param_type))
      end
    end

    DTO_PARAM_TYPES = {"Body" => "body", "Query" => "query"}
    DTO_TYPE_NAME   = /\A([A-Za-z_$][\w$]*)(?:\.[A-Za-z_$][\w$]*)*\s*(?:<[\s\S]*>)?\z/
    DTO_DECL_NAME   = /\b(?:class|interface)\s+([A-Za-z_$][\w$]*)/
    DTO_DEPTH_LIMIT = 6

    # Whether a whole-object `@Body()` / `@Query()` is read as its DTO's
    # fields. The other decorator-controller frameworks name their own
    # whole-object decorators (`@QueryParams`, `@BodyParams`).
    protected def reads_dto? : Bool
      true
    end

    # Param type => field names, for every whole-object `@Body()` /
    # `@Query()` whose declared type resolves to fields: an inline object
    # type, or a class/interface declared in the scan, with the fields it
    # inherits (`extends Base`, `PickType(Base, [...])`, ...).
    private def dto_params(params : Array(Noir::TsDecoratorExtractor::Parameter), file_path : String) : Hash(String, Array(String))
      result = {} of String => Array(String)
      return result unless reads_dto?
      params.each do |param|
        decorator = param.decorators.find { |d| DTO_PARAM_TYPES.has_key?(d.name) && param_decorator?(d) } || next
        # `@Body('field')` names one field; it is read elsewhere.
        next if decorator.args.first?.try(&.matches?(/\A['"`]/))
        type = param.type_text || next
        fields = type_fields(type, file_path, 0)
        next if fields.empty?
        names = result[DTO_PARAM_TYPES[decorator.name]] ||= [] of String
        fields.each { |name| names << name unless names.includes?(name) }
      end
      result
    end

    private def type_fields(type : String, from_path : String, depth : Int32) : Array(String)
      text = type.strip
      return Noir::TsClassFields.object_type_fields(text) if text.starts_with?('{')
      name = text.match(DTO_TYPE_NAME).try { text.split('<').first.split('.').last.strip } || return [] of String
      named_type_fields(name, from_path, depth)
    end

    private def named_type_fields(name : String, from_path : String, depth : Int32) : Array(String)
      return [] of String if depth > DTO_DEPTH_LIMIT
      decl, decl_path = find_type_decl(name, from_path) || return [] of String
      fields = decl.fields.dup
      decl.bases.each do |base|
        inherited = named_type_fields(base.name, decl_path, depth + 1)
        if pick = base.pick
          inherited = inherited.select { |field| pick.includes?(field) }
        end
        inherited.each { |field| fields << field unless fields.includes?(field) || base.omit.includes?(field) }
      end
      fields
    end

    NAMED_IMPORT   = /\bimport\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/
    STAR_REEXPORT  = /\bexport\s+\*\s+from\s*['"](\.[^'"]+)['"]/
    NAMED_REEXPORT = /\bexport\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"](\.[^'"]+)['"]/

    # The declaration of `name` visible from `from_path`: its own file's,
    # else the one its import resolves to (relative specifiers, through
    # `export *` / `export { }` barrels), else the scanned file declaring it
    # that shares the most directories with `from_path`. Two equally near
    # declarations are ambiguous: nil, so the caller keeps the generic param.
    # ponytail: package and tsconfig-path specifiers fall to the nearest
    # declaration; resolving them through tsconfig `paths` is the upgrade.
    private def find_type_decl(name : String, from_path : String) : Tuple(Noir::TsClassFields::Decl, String)?
      if decl = type_decls(from_path)[name]?
        return {decl, from_path}
      end
      if found = imported_type_decl(name, from_path)
        return found
      end
      candidates = (type_decl_index[name]? || return).reject(from_path).select { |path| type_decls(path).has_key?(name) }
      return if candidates.empty?
      best = candidates.max_of { |path| shared_dir_depth(path, from_path) }
      nearest = candidates.select { |path| shared_dir_depth(path, from_path) == best }
      {type_decls(nearest[0])[name], nearest[0]} if nearest.size == 1
    end

    private def imported_type_decl(name : String, from_path : String) : Tuple(Noir::TsClassFields::Decl, String)?
      read_file_content(from_path).scan(NAMED_IMPORT) do |imp|
        declared = imported_name(imp[1], name) || next
        return unless imp[2].starts_with?('.')
        target = Noir::ImportGraph.resolve_relative_import(from_path, imp[2], boundary: import_boundary_for(from_path)) || return
        return exported_type_decl(declared, target, 0)
      end
      nil
    rescue
      nil
    end

    # `name` as declared in `file` or re-exported by it from a relative module.
    private def exported_type_decl(name : String, file : String, depth : Int32) : Tuple(Noir::TsClassFields::Decl, String)?
      if decl = type_decls(file)[name]?
        return {decl, file}
      end
      return if depth >= 4
      content = read_file_content(file)
      content.scan(NAMED_REEXPORT) do |m|
        declared = imported_name(m[1], name) || next
        target = Noir::ImportGraph.resolve_relative_import(file, m[2], boundary: import_boundary_for(file)) || next
        return exported_type_decl(declared, target, depth + 1)
      end
      content.scan(STAR_REEXPORT) do |m|
        target = Noir::ImportGraph.resolve_relative_import(file, m[1], boundary: import_boundary_for(file)) || next
        if found = exported_type_decl(name, target, depth + 1)
          return found
        end
      end
      nil
    rescue
      nil
    end

    # The exported name behind local `name` in an `{ A, B as name }` list.
    private def imported_name(list : String, name : String) : String?
      list.split(',').each do |spec|
        declared, _, local = spec.strip.lchop("type ").partition(/\s+as\s+/)
        return declared.strip if (local.presence || declared).strip == name
      end
      nil
    end

    private def type_decls(path : String) : Hash(String, Noir::TsClassFields::Decl)
      cached = @nest_dto_mutex.synchronize { @nest_decls_by_file[path]? }
      return cached if cached
      decls = begin
        Noir::TsClassFields.declarations(Noir::JSRouteExtractor.strip_js_comments(read_file_content(path)))
      rescue
        {} of String => Noir::TsClassFields::Decl
      end
      @nest_dto_mutex.synchronize { @nest_decls_by_file[path] = decls }
    end

    private def type_decl_index : Hash(String, Array(String))
      @nest_dto_mutex.synchronize do
        @nest_decl_index ||= begin
          index = {} of String => Array(String)
          all_files.each do |path|
            next unless GLOBAL_LITERAL_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
            next if ignored_nest_path?(path)
            content = read_file_content(path)
            next unless content.includes?("class ") || content.includes?("interface ")
            content.scan(DTO_DECL_NAME) do |m|
              paths = index[m[1]] ||= [] of String
              paths << path unless paths.includes?(path)
            end
          rescue
            next
          end
          index
        end
      end
    end

    # Per-endpoint hook for a decorator-controller framework that reads
    # more off the method's decorators, the route decorator this endpoint
    # came from, and the class decorator that opened its controller.
    # `Endpoint` is a struct: only its arrays (params, tags) are shared.
    protected def route_decorated(endpoint : Endpoint, method : Noir::TsDecoratorExtractor::Method,
                                  route : Noir::TsDecoratorExtractor::Decorator, controller_decorator : String) : Nil
    end

    private def extract_interceptor_parameters(decorator_block : String, endpoint : Endpoint)
      decorator_block.scan(/(?:FileInterceptor|FilesInterceptor)\s*\(\s*['"`]([^'"`]+)['"`]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "body"))
      end

      decorator_block.scan(/FileFieldsInterceptor\s*\(\s*\[([\s\S]*?)\]/m) do |match|
        match[1].scan(/\bname\s*:\s*['"`]([^'"`]+)['"`]/) do |field|
          endpoint.push_param(Param.new(field[1], "", "body"))
        end
      end
    end

    REQUEST_DECORATORS = {"Req", "Request"}

    private def extract_request_object_params(body : String?, params : Array(Noir::TsDecoratorExtractor::Parameter), endpoint : Endpoint)
      return unless body
      request_names = [] of String
      params.each do |param|
        name = param.name || next
        next unless param.decorators.any? { |d| d.called && d.args.empty? && REQUEST_DECORATORS.includes?(d.name) }
        request_names << name unless request_names.includes?(name)
      end
      request_names << "req" if request_names.empty?

      # The dot/bracket field regexes are memoized per request-object name
      # ("req" dominates), so each pattern compiles once per scan instead
      # of once per handler.
      request_names.each do |name|
        REQUEST_OBJECT_FIELDS.each do |field, param_type|
          dot_re = cached_regex("nestjs:req_dot:#{name}:#{field}") { /\b#{Regex.escape(name)}\.#{field}\.(\w+)/ }
          bracket_re = cached_regex("nestjs:req_bracket:#{name}:#{field}") { /\b#{Regex.escape(name)}\.#{field}\s*\[\s*['"`]([^'"`]+)['"`]\s*\]/ }
          body.scan(dot_re) { |m| endpoint.push_param(Param.new(m[1], "", param_type)) }
          body.scan(bracket_re) { |m| endpoint.push_param(Param.new(m[1], "", param_type)) }
        end
      end
    end

    # Nest strips the trailing slash when it registers a route, so
    # `@Controller('/v2/me')` + `@Get('/')` serves `/v2/me`.
    private def combine_paths(base : String, route : String) : String
      # `@Controller()` + `@Get()` is the app root; an empty URL would be
      # dropped by the optimizer.
      return "/" if base.empty? && route.empty?
      path = if base.empty?
               route
             elsif route.empty?
               base
             else
               "#{base.chomp("/")}#{route.starts_with?("/") ? route : "/#{route}"}"
             end
      path.size > 1 && path.ends_with?('/') ? (path.rstrip('/').presence || "/") : path
    end

    private def extract_path_parameters(url : String, endpoint : Endpoint)
      # Extract path parameters from URL patterns like :id
      url.scan(/:(\w+)/) do |match|
        param_name = match[1]
        # push_param skips one already added by a @Param decorator
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end
  end
end
