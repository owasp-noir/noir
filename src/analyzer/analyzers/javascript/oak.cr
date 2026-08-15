require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/import_graph"
require "../../../models/code_locator"
require "../../../utils/url_path"

module Analyzer::Javascript
  # Oak's Router API is deliberately close to Koa's — `router.get(path,
  # handler)`, `:param` path syntax, a `ctx` handed to every handler — so
  # this analyzer largely mirrors `Analyzer::Javascript::Koa`: both share
  # `Noir::JSRouteExtractor` for verb-call extraction, path-param scanning,
  # and callee attachment. See `js_route_extractor.cr`'s `:oak` entry in
  # `SHARED_EXTRACTOR_FRAMEWORK_MARKERS` — it, and the Oak-specific
  # ctx.request.* param patterns added alongside it, are what make reuse
  # possible.
  #
  # Two shapes Oak supports that the shared JSParser already resolves with
  # no framework-specific code here:
  #
  #   * `new Router({ prefix: '/api/v1' })` — the constructor-level prefix
  #     is generic in `JSParser#scan_router_constructor_prefixes` (keyed on
  #     any `Router`-named constructor, not a specific framework).
  #   * `parent.use('/prefix', child.routes())` mounted **within the same
  #     file** — the generic same-file router-mount scan in
  #     `JSParser#parse_routes` handles this already (it only needs `child`
  #     to appear as a bare identifier inside the `.use(...)` call, and
  #     `child.routes()` still exposes `child` as that identifier).
  #
  # What the shared parser can't do — because it operates on one file's
  # token stream — is a router assembled in one file and mounted with a
  # prefix in another. `resolve_oak_mount_prefixes` below handles that
  # cross-file case, the same way `Koa#resolve_koa_mount_prefixes` does.
  class Oak < JavascriptEngine
    analyzer_for "js_oak"

    def analyze
      result = [] of Endpoint
      include_callee = callees_needed?

      resolve_oak_mount_prefixes

      parallel_file_scan([".ts", ".js", ".mjs"]) do |path|
        begin
          content = read_file_content(path)
          next if Noir::JSRouteExtractor.other_shared_extractor_framework?(content, :oak)
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
        rescue e
          logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
          analyze_with_regex(path, result)
        end
      end

      result
    end

    # Resolve cross-file Oak router mount prefixes and seed them into
    # CodeLocator under each imported child router's file key — the same
    # trick `Koa#resolve_koa_mount_prefixes` uses. A common Oak layout
    # aggregates sub-routers from separate files:
    #
    #   // routes/users.ts
    #   const router = new Router();
    #   router.get("/", handler);
    #   export default router;
    #
    #   // routes/index.ts
    #   import users from "./users.ts";
    #   const router = new Router();
    #   router.use("/users", users.routes());
    #
    # so `routes/users.ts`'s routes need the `/users` prefix even though
    # the mounting line lives in a different file.
    private def resolve_oak_mount_prefixes
      locator = CodeLocator.instance
      boundary = @base_path

      all_files.each do |path|
        next unless [".ts", ".js", ".mjs", ".cjs"].any? { |ext| path.ends_with?(ext) }
        content = read_file_content(path)
        # Cheap gate: the mount chain always pairs `.use(` with `.routes(`.
        next unless content.includes?(".use(") && content.includes?(".routes(")
        next if Noir::JSRouteExtractor.minified_content?(content)

        # Map local identifiers to the router file they import. Oak
        # projects are ESM-only in the overwhelming majority of cases
        # (`import x from "./x.ts"`), but a `require(...)` scan is kept
        # too — cheap, and harmless if it never matches.
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
        # the no-prefix parent.use(child[.routes()]). The `.routes()`
        # suffix on `child` is optional — a sub-router file may export
        # the pre-called `router.routes()` directly, in which case the
        # mount site sees a bare identifier. Unlike koa-router, Oak's
        # `.use()` on a router routinely takes a third argument
        # (`child.allowedMethods()`), so — unlike the plain koa-router
        # regex — neither pattern requires the call to close right after
        # `child`.
        edges = [] of Tuple(String, String, String)
        content.scan(/(\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)(?:\.routes\s*\(\s*\))?/) do |m|
          edges << {m[1], m[2], m[3]} if m.size >= 4
        end
        content.scan(/(\w+)\.use\s*\(\s*(\w+)(?:\.routes\s*\(\s*\))?/) do |m|
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
        logger.debug "oak mount prefix resolution failed for #{path}: #{e.message}"
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

    private def analyze_with_regex(path : String, result : Array(Endpoint))
      file_content = read_file_content(path)
      # Regex fallback for when the JSParser trips over a file (rare, but
      # more likely on Deno/TS sources that lean on newer TS syntax).
      # Covers router.get('/path', ...) / router.post(...) / ... and the
      # constructor-level `new Router({ prefix: '/x' })` recipe — the
      # cross-file `.use('/prefix', child.routes())` mount chain is
      # already resolved ahead of time by `resolve_oak_mount_prefixes`
      # and read back through `CodeLocator`, same as the primary path.

      router_prefixes = {} of String => String

      file_content.scan(/const\s+(\w+)\s*=\s*new\s+Router\(\s*{\s*prefix:\s*['"]([^'"]+)['"]\s*}?\s*\)/) do |match|
        router_prefixes[match[1]] = match[2]
      end

      file_content.scan(/(\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)\.routes\(\s*\)/) do |match|
        parent_router = match[1]
        prefix = match[2]
        child_router_name = match[3]

        base_prefix = router_prefixes.fetch(parent_router, "")
        router_prefixes[child_router_name] = File.join(base_prefix, prefix)
      end

      locator = CodeLocator.instance
      lookup_key = Analyzer::Javascript::ExpressConstants.file_key(File.expand_path(path))
      file_prefixes = locator.all(lookup_key)

      file_content.scan(/(?:(\w+)\.|app\.)(get|post|put|delete|del|patch|options|head|all)\s*\(\s*['"]([^'"]+)['"]/) do |match|
        router_var = match[1]
        http_method = Noir::JSRouteExtractor.normalize_http_method(match[2])
        route_path = match[3]

        current_prefix = ""
        if router_var && router_prefixes.has_key?(router_var)
          current_prefix = router_prefixes[router_var]
        elsif !file_prefixes.empty?
          current_prefix = file_prefixes.first
        end

        full_path = File.join(current_prefix, route_path)
        full_path = "/" if full_path.empty?
        full_path = "/#{full_path}" unless full_path.starts_with?('/')

        endpoint = Endpoint.new(full_path, http_method)
        endpoint.details = Details.new(PathInfo.new(path, 1))

        route_path.scan(/:(\w+)/) do |m|
          if m.size > 0 && !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
            endpoint.push_param(Param.new(m[1], "", "path"))
          end
        end

        extract_oak_params_from_content(file_content, router_var || "app", match[2], route_path, endpoint)

        unless result.any? { |e| e.url == full_path && e.method == http_method }
          result << endpoint
        end
      end
    end

    # Extract parameters from an Oak handler body, for the regex-fallback
    # path only — the primary path gets these for free through
    # `Noir::JSRouteExtractor.extract_params_from_context`, which already
    # carries the Oak-specific ctx.request.* patterns.
    private def extract_oak_params_from_content(content : String, router_name : String, method : String, path : String, endpoint : Endpoint)
      handler_pattern = /#{Regex.escape(router_name)}\.#{method}\s*\(\s*['"]#{Regex.escape(path)}['"][^{]*\{([^}]*(?:\{[^}]*\})*[^}]*)\}/m

      match = content.match(handler_pattern)
      return unless match && match.size > 1

      handler_body = match[1]
      return if handler_body.empty?

      handler_body.scan(/ctx\.request\.url\.searchParams\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 0
      end

      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+ctx\.request\.body\.json\s*\(/) do |m|
        if m.size > 0
          m[1].split(",").map(&.strip).each do |param|
            clean_param = param.split("=").first.strip.split(":").first.strip
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      handler_body.scan(/ctx\.request\.headers\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "header")) if m.size > 0
      end

      handler_body.scan(/ctx\.cookies\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "cookie")) if m.size > 0
      end

      handler_body.scan(/ctx\.params\.(\w+)/) do |m|
        if m.size > 0 && !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
          endpoint.push_param(Param.new(m[1], "", "path"))
        end
      end
    end
  end
end
