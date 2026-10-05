require "./remix"
require "../../../miniparsers/react_router_config_extractor_ts"

module Analyzer::Javascript
  # React Router v7 framework mode — the Remix successor. Route modules
  # are Remix's (`loader` / `action` exports, a default-exported page), so
  # this rides the Remix analyzer; what differs is where routes come from.
  #
  # `app/routes.ts` declares them:
  #
  #   index("routes/home.tsx")              → GET /
  #   route("users/:id", "routes/user.tsx") → /users/{id}, verbs from the module
  #   ...(await flatRoutes())               → the Remix `app/routes/` convention
  #
  # The file convention therefore applies only where the config spreads
  # `flatRoutes()` in. A project with no config — or one whose config reads
  # as nothing we recognise — falls back to it rather than report nothing.
  #
  # Out of scope: `flatRoutes({ rootDirectory })` and a non-default
  # `appDirectory` for the file convention (config routes resolve against
  # whatever directory holds `routes.ts`, so those are covered).
  class ReactRouter < Remix
    analyzer_for "js_react_router"

    PACKAGE_MARKERS  = ["@react-router/dev"]
    CONFIG_BASENAMES = ["react-router.config.ts", "react-router.config.js", "react-router.config.mjs", "react-router.config.cjs"]

    ROUTE_CONFIG_BASENAMES = ["routes.ts", "routes.js", "routes.mts", "routes.mjs"]
    ROUTE_CONFIG_MARKER    = "@react-router/"

    def analyze
      result = [] of Endpoint
      include_callee = callees_needed?
      roots = project_roots

      # Expanded path → path as scanned, so a config's `routes/user.tsx`
      # lands on the same path string every other endpoint reports.
      modules = {} of String => String
      get_files_by_extensions(EXTENSIONS).each do |path|
        modules[Noir::PathScope.expand(path)] = path if path_under_project_roots?(path, roots)
      end

      # Expanded app directory → whether its config opts into the file convention.
      flat_dirs = {} of String => Bool
      modules.each do |expanded, config_path|
        next unless ROUTE_CONFIG_BASENAMES.includes?(File.basename(config_path))
        content = read_file_content(config_path) rescue next
        next unless content.includes?(ROUTE_CONFIG_MARKER)

        app_dir = File.dirname(expanded)
        config = Noir::TreeSitterReactRouterConfigExtractor.extract(content)
        flat_dirs[app_dir] = config.flat_routes? || config.routes.empty?

        config.routes.each do |route|
          url = config_url(route.path)
          if module_path = modules[File.expand_path(route.file, app_dir)]?
            endpoints = module_endpoints(url, module_path, include_callee)
            result.concat(endpoints) if endpoints
          else
            # Declared, but the module is outside the scan: the URL still exists.
            result << file_route_endpoint(url, "GET", config_path, route.line)
          end
        end
      end

      mutex = Mutex.new
      parallel_file_scan(EXTENSIONS) do |path|
        next unless path_under_project_roots?(path, roots)
        next unless name = flat_route_name(path, flat_dirs)

        endpoints = module_endpoints(url_for(name), path, include_callee)
        mutex.synchronize { result.concat(endpoints) } if endpoints
      end

      result
    end

    private def project_roots : Array(String)
      discover_js_project_roots(PACKAGE_MARKERS, CONFIG_BASENAMES)
    end

    private def flat_route_name(path : String, flat_dirs : Hash(String, Bool)) : String?
      app_dir, name = flat_route(Noir::PathScope.expand(path)) || return
      flat = flat_dirs[app_dir]?
      flat.nil? ? flat_route_name(path) : (name if flat)
    end

    # `users/:id` → `/users/{id}`, `:lang?` → `{lang}`, `*` → `{splat}`
    # (Remix's name for the same catch-all).
    private def config_url(path : String) : String
      url = path.split('/').map do |segment|
        segment = segment.rchop('?')
        if segment == "*"
          "{splat}"
        elsif segment.starts_with?(':')
          "{#{segment[1..]}}"
        else
          segment
        end
      end.join('/')
      url = url.rstrip('/')
      url.starts_with?('/') ? url : "/#{url}"
    end
  end
end
