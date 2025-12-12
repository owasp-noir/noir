require "../../../models/analyzer"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Koa < Analyzer
    def analyze
      channel = Channel(String).new
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          worker_count = @options["concurrency"].to_s.to_i
          worker_count = 16 if worker_count > 16
          worker_count = 1 if worker_count < 1
          worker_count.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next unless [".js", ".ts", ".mjs"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    begin
                      content = File.read(path, encoding: "utf-8", invalid: :skip)
                      parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug)
                      parser_endpoints.each do |endpoint|
                        details = Details.new(PathInfo.new(path, 1)) # Line number is approximate
                        endpoint.details = details

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

                      # Extract static path declarations
                      Noir::JSRouteExtractor.extract_static_paths(content).each do |static_path|
                        static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
                      end
                    rescue e
                      logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
                      analyze_with_regex(path, result, static_dirs)
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue e : Exception
                  logger.debug "Error processing file #{path}: #{e.message}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error in Koa analyzer: #{e.message}"
      end

      # Process static directories to create endpoints for static files
      process_static_dirs(static_dirs, result)

      result
    end

    # Process static directories and add endpoints for each file
    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      static_dirs.each do |dir|
        full_path = (base_path + "/" + dir["file_path"]).gsub_repeatedly("//", "/")
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        get_files_by_prefix(full_path).each do |file_path|
          if File.exists?(file_path)
            # Use lchop to only remove from the beginning of the string
            relative_path = file_path.starts_with?(full_path) ? file_path.lchop(full_path) : file_path
            url = static_path == "/" ? relative_path : "#{static_path}#{relative_path}"
            url = "/#{url}" unless url.starts_with?("/")

            details = Details.new(PathInfo.new(file_path))
            endpoint = Endpoint.new(url, "GET", details)
            result << endpoint unless result.any? { |e| e.url == url && e.method == "GET" }
          end
        end
      end
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)) = [] of Hash(String, String))
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file_content = file.gets_to_end
        # Regex for Koa router: router.get('/path', ...) or app.get('/path', ...)
        # Covers .get, .post, .put, .del, .patch, .all
        # Also captures router prefixes like router.use('/prefix', subRouter.routes())

        router_prefixes = {} of String => String # To store router variable name and its prefix

        # Extract static paths
        Noir::JSRouteExtractor.extract_static_paths(file_content).each do |static_path|
          static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
        end

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
          full_path = "/" if full_path == "" # Handle empty path case
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
