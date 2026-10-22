require "../../engines/javascript_engine"

module Analyzer::Javascript
  class Nitro < JavascriptEngine
    analyzer_for "js_nitro"

    def analyze
      result = [] of Endpoint
      # `(routes root, url, method)` -> index into `result`.
      #
      # The dedup this backs used to be `result.index { |e| e.url == url &&
      # e.method == method }` — a lookup across the whole scan, with no
      # notion of which Nitro app the route belonged to. Two Nitro projects
      # under one scan base (a monorepo, or a repo that keeps an example app
      # beside the real one) both define `routes/users.post.ts`, and the
      # second one to be read overwrote the first: its params, its callees
      # and its `code_path` all disappeared, and the survivor was whichever
      # worker fiber finished last. Same input, different report between
      # runs. Keying on the routes root keeps each app's route separate and
      # lets the optimizer merge them, which is where duplicate endpoints
      # are supposed to be resolved.
      seen = {} of Tuple(String, String, String) => Int32
      mutex = Mutex.new
      include_callee = callees_needed?
      # `routes/` on its own is not a Nitro signal — it is the conventional
      # name for a router directory in Koa, Express, Fastify and most other JS
      # frameworks. Treating every `*/routes/*.ts` in the scan as a Nitro
      # file-system route meant that in any repo holding a second JS project,
      # each of those files became seven phantom endpoints (one per HTTP verb,
      # since a bare file names no method): 42 out of the Koa fixture alone,
      # against 10 from the real Nitro one. Scope to the Nitro project root
      # the same way the SvelteKit analyzer does; with no marker found,
      # `path_under_project_roots?` waves everything through, so a Nitro
      # project detected only by a `nitropack` import still resolves.
      project_roots = discover_js_project_roots(
        ["nitropack"],
        ["nitro.config.js", "nitro.config.ts", "nitro.config.mjs", "nitro.config.cjs"]
      )

      parallel_file_scan([".js", ".ts", ".mjs", ".mts"]) do |path|
        api_dir = nitro_api_dir(path, project_roots)
        next unless api_dir || path.includes?("/routes/")
        next unless path_under_project_roots?(path, project_roots)
        analyze_nitro_file(path, api_dir, result, seen, mutex, include_callee)
      end

      result
    end

    # Nitro also serves `<srcDir>/api/` under `/api`, where srcDir is the
    # project root or its `server/`. Unlike `routes/`, `api/` is only read
    # directly under a discovered root: it is too common a directory name
    # (`utils/api/`, `apps/api/`, Next's `pages/api/`) to trust anywhere
    # else, and with no root found it is not read at all.
    private def nitro_api_dir(path : String, roots : Array(String)) : String?
      expanded = Noir::PathScope.expand(path)
      roots.each do |root|
        {"/api/", "/server/api/"}.each do |dir|
          prefix = root + dir
          return prefix if expanded.starts_with?(prefix)
        end
      end
      nil
    end

    private def analyze_nitro_file(path : String, api_dir : String?, result : Array(Endpoint),
                                   seen : Hash(Tuple(String, String, String), Int32),
                                   mutex : Mutex, include_callee : Bool)
      # Extract endpoint from file path
      # routes/hello.ts -> /hello
      # routes/users/[id].ts -> /users/:id
      # routes/users.get.ts -> /users (GET only)
      # routes/api/items.ts -> /api/items
      # api/items.get.ts -> /api/items (GET only)

      # Scan-base-relative, never absolute: `String#index` takes the
      # FIRST occurrence, so a same-named directory above the scan base
      # won outright and the derived URL changed with the checkout path.
      if api_dir
        # `api_dir` is absolute, so it is made base-relative against the
        # expanded base, not through `base_relative_path`.
        return if in_test_tree?(Noir::PathScope.base_relative(api_dir, Noir::PathScope.expand(configured_base_for(path))))

        # The api dir itself is the dedup scope, so an `api/x.get.ts` and a
        # `routes/api/x.get.ts` stay two endpoints for the optimizer to merge.
        routes_root = api_dir
        relative_path = "api/" + Noir::PathScope.expand(path)[api_dir.size..]
      else
        scoped = base_relative_path(path)
        base_path_idx = scoped.index("/routes/")
        return if base_path_idx.nil? || in_test_tree?(scoped[0...base_path_idx])

        # Everything above `routes/` identifies the Nitro app this file
        # belongs to — the dedup scope below.
        routes_root = scoped[0...base_path_idx]

        # Get the path after /routes/
        relative_path = scoped[(base_path_idx + "/routes/".size)..-1]
      end

      # Remove file extension
      relative_path = relative_path.gsub(/\.(js|ts|mjs|mts)$/, "")

      # Check for HTTP method-specific files (e.g., users.get.ts)
      http_methods = ["get", "post", "put", "delete", "patch", "head", "options"]
      specific_method = nil

      http_methods.each do |method|
        if relative_path.ends_with?(".#{method}")
          specific_method = method.upcase
          relative_path = relative_path[0..-(method.size + 2)]
          break
        end
      end

      # Convert [id] to :id for dynamic routes
      relative_path = relative_path.gsub(/\[(\w+)\]/, ":\\1")

      # Convert [...slug] and unnamed [...] catch-all routes
      relative_path = relative_path.gsub(/\[\.\.\.\w*\]/, "*")

      # Build the URL
      url = "/#{relative_path}"

      # Clean up double slashes
      url = url.gsub("//", "/")

      # Handle index routes
      url = url.gsub(/\/index$/, "")
      url = "/" if url.empty?

      # Determine HTTP methods
      methods = specific_method ? [specific_method] : ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

      # Read file content to extract parameters
      begin
        content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
        h3_params = h3_event_params(content)
        callees = include_callee ? Noir::JSCalleeExtractor.callees_for_default_event_handler(content, path, language: javascript_source_language(path)) : [] of Noir::JSCalleeExtractor::Entry

        methods.each do |method|
          endpoint = Endpoint.new(url, method)
          details = Details.new(PathInfo.new(path, 1))
          endpoint.details = details

          # Extract path parameters from URL
          url.scan(/:(\w+)/) do |m|
            if m.size > 0
              param = Param.new(m[1], "", "path")
              endpoint.push_param(param)
            end
          end

          # Same h3 request helpers as Nuxt server routes.
          h3_params.each { |param| endpoint.push_param(param) }

          attach_js_callees(endpoint, callees) if include_callee

          mutex.synchronize do
            key = {routes_root, url, method}
            if existing_idx = seen[key]?
              # Method-specific files take precedence over generic handlers
              # *within the same app*: `routes/users.post.ts` wins over the
              # POST that `routes/users.ts` implies.
              result[existing_idx] = endpoint if specific_method
            else
              seen[key] = result.size
              result << endpoint
            end
          end
        end
      rescue e : Exception
        logger.debug "Error reading file #{path}: #{e.message}"
      end
    end
  end
end
