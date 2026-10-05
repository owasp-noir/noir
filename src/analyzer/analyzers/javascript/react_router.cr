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
  # `flatRoutes()` in. A config that reads as nothing we recognise, or a
  # scan with no config at all, falls back to it rather than report nothing.
  #
  # Out of scope: `flatRoutes({ rootDirectory })` and a non-default
  # `appDirectory` for the file convention (config routes resolve against
  # whatever directory holds `routes.ts`, so those are covered), and route
  # arrays imported from another file, which are not followed — a split-out
  # `routes.ts` is still read on its own, without the importer's prefix.
  class ReactRouter < Remix
    analyzer_for "js_react_router"

    PACKAGE_MARKERS  = ["@react-router/dev"]
    CONFIG_BASENAMES = ["react-router.config.ts", "react-router.config.js", "react-router.config.mjs", "react-router.config.cjs"]

    def analyze
      result = [] of Endpoint
      include_callee = callees_needed?
      apps = react_router_apps

      # Expanded path → path as scanned, so a config's `routes/user.tsx`
      # lands on the same path string every other endpoint reports.
      modules = {} of String => String
      unless apps.empty?
        get_files_by_extensions(EXTENSIONS).each { |path| modules[Noir::PathScope.expand(path)] = path }
      end

      # Expanded app directory → whether it opts into the file convention.
      flat_dirs = {} of String => Bool
      apps.each do |app_dir, config_paths|
        flat = false
        declared = false
        config_paths.each do |config_path|
          config = begin
            Noir::TreeSitterReactRouterConfigExtractor.extract(read_file_content(config_path))
          rescue e
            logger.debug "Error reading route config #{config_path}: #{e.message}"
            Noir::SkippedFiles.record(tech, config_path, e.message.presence || e.class.name)
            next
          end
          flat ||= config.flat_routes?
          declared ||= !config.routes.empty?

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
        # A config that declares nothing we read (a community convention such
        # as `autoRoutes()`) falls back to the file convention.
        flat_dirs[app_dir] = flat || !declared
      end

      roots = project_roots
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

    # Every React Router app has a route config, so once the scan holds any,
    # an app directory without one is not React Router's (a Remix app under
    # the same root). With none at all, the Remix convention stands in.
    private def flat_route_name(path : String, flat_dirs : Hash(String, Bool)) : String?
      return flat_route_name(path) if flat_dirs.empty?
      app_dir, name = flat_route(Noir::PathScope.expand(path)) || return
      name if flat_dirs[app_dir]?
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
