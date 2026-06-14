require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/import_graph"
require "../../../models/code_locator"
require "../../../utils/url_path"

module Analyzer::Javascript
  class Koa < JavascriptEngine
    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      include_callee = callees_needed?

      # koa-router mounts sub-routers through a `.routes()` middleware
      # chain that the Express-oriented mount scanner can't model:
      #   const api = new Router()
      #   api.use(usersRouter)                 // usersRouter = require('./users-router')
      #   router.use('/api', api.routes())     // api aggregated under /api
      # Resolve those chains up front and seed each imported child file's
      # prefix into CodeLocator so the per-file pass emits `/api/users`
      # instead of a bare `/users`.
      resolve_koa_mount_prefixes

      parallel_file_scan([".js", ".ts", ".mjs"]) do |path|
        begin
          content = read_file_content(path)
          parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
            include_callees: include_callee)
          parser_endpoints.each do |endpoint|
            if endpoint.details.code_paths.empty?
              endpoint.details = Details.new(PathInfo.new(path))
            end

            if endpoint.url.includes?(":")
              endpoint.url.scan(/:(\w+)/) do |m|
                if m.size > 0
                  param = Param.new(m[1], "", "path")
                  endpoint.push_param(param) if !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
                end
              end
            end
            result << endpoint
          end

          collect_static_paths(path, content, static_dirs, :koa)

          # Strapi-style declarative routes: `{ method: 'GET',
          # path: '/foo', handler: '...' }` object literals,
          # typically exported as an array from
          # `<plugin>/server/routes/**/*.js`. The verb DSL (`app.get`,
          # `router.post`) doesn't fire on these — strapi/strapi
          # parks ~38 such routes per plugin that the shared
          # JSRouteExtractor would otherwise miss.
          extract_strapi_routes(path, content, result)
        rescue e
          logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
          analyze_with_regex(path, result, static_dirs)
        end
      end

      # Process static directories to create endpoints for static files
      process_static_dirs(static_dirs, result)

      result
    end

    # Resolve koa-router cross-file mount prefixes and seed them into
    # CodeLocator under each imported child router's file key. Each file
    # that does the mounting is resolved independently — the common layout
    # has one aggregator file (`routes/index.js`) wiring every sub-router.
    private def resolve_koa_mount_prefixes
      locator = CodeLocator.instance
      boundary = @base_path

      all_files.each do |path|
        next unless [".js", ".ts", ".mjs", ".cjs"].any? { |ext| path.ends_with?(ext) }
        content = read_file_content(path)
        # Cheap gate: the mount chain always pairs `.use(` with `.routes(`.
        next unless content.includes?(".use(") && content.includes?(".routes(")
        next if Noir::JSRouteExtractor.minified_content?(content)

        # Map local identifiers to the router file they import.
        imports = Hash(String, String).new
        record_import = ->(var : String, spec : String) do
          resolved = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: boundary)
          imports[var] = resolved if resolved
        end
        content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
          record_import.call(m[1], m[2]) if m.size >= 3
        end
        content.scan(/import\s+(\w+)\s+from\s+['"]([^'"]+)['"]/) do |m|
          record_import.call(m[1], m[2]) if m.size >= 3
        end

        # Collect mount edges: parent.use('/prefix', child[.routes()]) and
        # the no-prefix parent.use(child[.routes()]). A bare `child` or a
        # `child.routes()` wrapper is a router; a `factory()` call (e.g.
        # `bodyParser()`) is middleware and never matches these shapes.
        edges = [] of Tuple(String, String, String)
        content.scan(/(\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)(?:\.routes\s*\(\s*\))?\s*\)/) do |m|
          edges << {m[1], m[2], m[3]} if m.size >= 4
        end
        content.scan(/(\w+)\.use\s*\(\s*(\w+)(?:\.routes\s*\(\s*\))?\s*\)/) do |m|
          edges << {m[1], "", m[2]} if m.size >= 3
        end
        next if edges.empty?

        prefixes = resolve_mount_edge_prefixes(edges)

        prefixes.each do |router_var, router_prefixes|
          file = imports[router_var]?
          next unless file
          key = Analyzer::Javascript::ExpressConstants.file_key(File.expand_path(file))
          router_prefixes.each do |prefix|
            next if prefix.empty?
            locator.push(key, prefix) unless locator.all(key).includes?(prefix)
          end
        end
      rescue e
        logger.debug "koa mount prefix resolution failed for #{path}: #{e.message}"
      end
    end

    # Resolve every router variable's mount prefix(es) from the edge list.
    # A variable that is never mounted into another (a root aggregator like
    # the exported `router`) carries the empty prefix; children inherit the
    # parent's prefix joined with the edge's own prefix. Iterated to a
    # fixpoint so a two-level chain (root -> api -> child) fully resolves.
    private def resolve_mount_edge_prefixes(edges : Array(Tuple(String, String, String))) : Hash(String, Array(String))
      children = edges.map { |_, _, child| child }.to_set
      prefixes = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }

      # Seed roots (never a mount target) with the empty prefix.
      edges.each do |parent, _, _|
        prefixes[parent] << "" if !children.includes?(parent) && prefixes[parent].empty?
      end

      max_iterations = 16
      iterations = 0
      changed = true
      while changed && iterations < max_iterations
        changed = false
        iterations += 1
        edges.each do |parent, prefix, child|
          # Propagate only from a resolved parent (a seeded root or an
          # already-resolved child). Defaulting an unresolved parent to ""
          # would leak a wrong prefix (`/sub` instead of `/api/sub`).
          parent_prefixes = prefixes[parent]?
          next if parent_prefixes.nil? || parent_prefixes.empty?
          parent_prefixes.each do |pp|
            combined = if pp.empty?
                         prefix
                       elsif prefix.empty?
                         pp
                       else
                         Noir::URLPath.join(pp, prefix)
                       end
            unless prefixes[child].includes?(combined)
              prefixes[child] << combined
              changed = true
            end
          end
        end
      end

      prefixes
    end

    # Match Strapi's declarative route entries: object literals
    # whose `method:` and `path:` keys sit on adjacent lines. Both
    # keys are bare identifiers (Strapi never quotes them) and the
    # values are single-quoted strings (the convention across every
    # `@strapi/plugin-*` route file).
    private def extract_strapi_routes(path : String, content : String, result : Array(Endpoint))
      return unless strapi_route_candidate?(content)

      seen = Set(Tuple(String, String, Int32)).new
      lines = content.lines
      lines.each_with_index do |line, index|
        next unless m = line.match(/^\s*method:\s*['"]([A-Z]+)['"]\s*,?/)
        method = m[1].upcase
        next unless ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].includes?(method)
        # Strapi route objects carry `method`, `path`, and `handler`.
        # Requiring the handler keeps generic HTTP client/config objects
        # like `{ method: 'GET', path: '/health' }` from becoming Koa
        # endpoints just because the project imports Koa elsewhere.
        path_str = nil.as(String?)
        handler_seen = false
        object_depth = 1
        (0..16).each do |off|
          next unless idx = index + off
          next unless idx < lines.size
          candidate = lines[idx]
          if pm = candidate.match(/(?:^\s*|[,{]\s*)path:\s*['"]([^'"]+)['"]/)
            path_str = pm[1]
          end
          handler_seen = true if candidate.match(/(?:^\s*|[,{]\s*)handler:\s*['"][^'"]+['"]/)
          if off > 0
            object_depth += candidate.count('{') - candidate.count('}')
            break if object_depth <= 0
          end
        end
        next unless route_path = path_str
        next unless handler_seen
        # Skip duplicate (same triple already emitted for this file).
        key = {method, route_path, index + 1}
        next if seen.includes?(key)
        seen << key

        details = Details.new(PathInfo.new(path, index + 1))
        endpoint = Endpoint.new(route_path, method, details)
        if route_path.includes?(":")
          route_path.scan(/:(\w+)/) do |pm|
            next unless pm.size > 0
            endpoint.push_param(Param.new(pm[1], "", "path"))
          end
        end
        result << endpoint
      end
    end

    private def strapi_route_candidate?(content : String) : Bool
      content.includes?("method:") &&
        content.includes?("path:") &&
        content.includes?("handler:")
    end

    # Process static directories and add endpoints for each file
    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      process_js_static_dirs(static_dirs, result)
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)) = [] of Hash(String, String))
      file_content = read_file_content(path)
      # Regex for Koa router: router.get('/path', ...) or app.get('/path', ...)
      # Covers .get, .post, .put, .del, .patch, .all
      # Also captures router prefixes like router.use('/prefix', subRouter.routes())

      router_prefixes = {} of String => String # To store router variable name and its prefix

      collect_static_paths(path, file_content, static_dirs, :koa)

      # Detect router prefixes
      # Example: const adminRouter = new Router({ prefix: '/admin' });
      # Example: router.use('/api/v1', apiV1Router.routes());
      file_content.scan(/const\s+(\w+)\s*=\s*new\s+Router\(\s*{\s*prefix:\s*['"]([^'"]+)['"]\s*}\s*\)/) do |match|
        router_name = match[1]
        prefix = match[2]
        router_prefixes[router_name] = prefix
      end

      file_content.scan(/(\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)\.routes\(\s*\)/) do |match|
        parent_router = match[1] # This could be app or another router
        prefix = match[2]
        child_router_name = match[3]

        base_prefix = router_prefixes.fetch(parent_router, "")
        full_prefix = File.join(base_prefix, prefix)
        router_prefixes[child_router_name] = full_prefix
      end

      # Detect routes
      # Example: router.get('/users', ctx => { ... });
      # Example: app.get('/status', async (ctx) => { ... });
      file_content.scan(/(?:(\w+)\.|app\.)(get|post|put|delete|del|patch|all)\s*\(\s*['"]([^'"]+)['"]/) do |match|
        router_var = match[1] # Can be nil if it's app.get directly
        http_method = Noir::JSRouteExtractor.normalize_http_method(match[2])
        route_path = match[3]

        current_prefix = ""
        if router_var && router_prefixes.has_key?(router_var)
          current_prefix = router_prefixes[router_var]
        end

        full_path = File.join(current_prefix, route_path)
        full_path = "/" if full_path.empty? # Handle empty path case
        full_path = "/#{full_path}" unless full_path.starts_with?('/')

        endpoint = Endpoint.new(full_path, http_method)
        details = Details.new(PathInfo.new(path, 1)) # Approximate line number
        endpoint.details = details

        # Extract path parameters from the route_path itself
        route_path.scan(/:(\w+)/) do |m|
          if m.size > 0 && !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
            param = Param.new(m[1], "", "path")
            endpoint.push_param(param)
          end
        end

        # Extract parameters from handler body
        extract_koa_params_from_content(file_content, router_var || "app", match[2], route_path, endpoint)

        unless result.any? { |e| e.url == full_path && e.method == http_method }
          result << endpoint
        end
      end
    end

    # Extract parameters from Koa handler body
    private def extract_koa_params_from_content(content : String, router_name : String, method : String, path : String, endpoint : Endpoint)
      # Find the route handler function
      handler_pattern = /#{Regex.escape(router_name)}\.#{method}\s*\(\s*['"]#{Regex.escape(path)}['"][^{]*\{([^}]*(?:\{[^}]*\})*[^}]*)\}/m

      match = content.match(handler_pattern)
      return unless match && match.size > 1

      handler_body = match[1]
      return if handler_body.empty?

      # Extract query parameters - Koa style: ctx.query.X, ctx.query['X'], ctx.request.query.X
      handler_body.scan(/ctx\.query\.(\w+)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 0
      end

      handler_body.scan(/ctx\.query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 0
      end

      handler_body.scan(/ctx\.request\.query\.(\w+)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 0
      end

      # Extract body parameters - Koa style: ctx.request.body.X, const { X } = ctx.request.body
      handler_body.scan(/ctx\.request\.body\.(\w+)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "json")) if m.size > 0
      end

      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*ctx\.request\.body/) do |m|
        if m.size > 0
          params = m[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = param.split("=").first.strip.split(":").first.strip
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      # Extract header parameters - Koa style: ctx.headers['X'], ctx.header['X'], ctx.get('X')
      handler_body.scan(/ctx\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "header")) if m.size > 0
      end

      handler_body.scan(/ctx\.header\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "header")) if m.size > 0
      end

      handler_body.scan(/ctx\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "header")) if m.size > 0
      end

      # Extract cookie parameters - Koa style: ctx.cookies.get('X')
      handler_body.scan(/ctx\.cookies\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "cookie")) if m.size > 0
      end

      # Extract path parameters from ctx.params.X
      handler_body.scan(/ctx\.params\.(\w+)/) do |m|
        if m.size > 0 && !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
          endpoint.push_param(Param.new(m[1], "", "path"))
        end
      end
    end
  end
end
