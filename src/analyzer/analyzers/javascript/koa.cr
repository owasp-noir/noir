require "../../../models/analyzer"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Koa < Analyzer
    def analyze
      channel = Channel(String).new
      result = [] of Endpoint

      begin
        spawn do
          Dir.glob("#{@base_path}/**/*") do |file|
            channel.send(file)
          end
          channel.close
        end

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next unless [".js", ".ts", ".mjs"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    begin
                      parser_endpoints = Noir::JSRouteExtractor.extract_routes(path)
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
                    rescue e
                      logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
                      analyze_with_regex(path, result)
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

      result
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint))
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file_content = file.gets_to_end
        # Regex for Koa router: router.get('/path', ...) or app.get('/path', ...)
        # Covers .get, .post, .put, .del, .patch, .all
        # Also captures router prefixes like router.use('/prefix', subRouter.routes())

        router_prefixes = {} of String => String # To store router variable name and its prefix

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

          # Simple heuristic for body params (ctx.request.body.paramName)
          # This is a very basic check and might need refinement.
          # We need to find the handler block for this route to do it more accurately.
          # For now, we'll skip complex body/query/header param extraction in regex fallback.

          unless result.any? { |e| e.url == full_path && e.method == http_method }
            result << endpoint
          end
        end
      end
    end
  end
end
