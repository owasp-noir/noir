require "../../../models/analyzer"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Fastify < Analyzer
    def analyze
      # Source Analysis
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
                  # Use any? with an array of extensions
                  next unless [".js", ".ts", ".jsx", ".tsx"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    # First try to use the JS parser for more robust analysis
                    begin
                      content = File.read(path, encoding: "utf-8", invalid: :skip)
                      parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug)
                      parser_endpoints.each do |endpoint|
                        # Add file location details
                        details = Details.new(PathInfo.new(path, 1)) # Line number is approximate
                        endpoint.details = details

                        # Parse path parameters from the URL path itself
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

                      # Fallback to the original regex-based approach if parser fails
                      analyze_with_regex(path, result, static_dirs)
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue e : Exception
                  logger.debug "Error processing file #{path}: #{e.message}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error in Fastify analyzer: #{e.message}"
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

    # Helper method to create an endpoint with details
    private def create_endpoint(path : String, url : String, method : String, params : Array(Param)) : Endpoint
      endpoint = Endpoint.new(url, method)
      endpoint.details = Details.new(PathInfo.new(path, 1))
      params.each do |param|
        endpoint.push_param(param)
      end
      endpoint
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)) = [] of Hash(String, String))
      # Original regex-based analysis as a fallback
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        last_endpoint = Endpoint.new("", "")
        # current_router_base = ""
        fastify_instances = [] of String
        route_plugin_prefixes = {} of String => String
        plugin_functions = {} of String => Bool
        file_content = file.gets_to_end

        # Extract static paths
        Noir::JSRouteExtractor.extract_static_paths(file_content).each do |static_path|
          static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
        end

        # First scan for fastify instances and plugin registrations
        file_content.each_line do |line|
          # Detect Fastify initialization
          if line =~ /(?:const|let|var)\s+(\w+)\s*=\s*(?:require\s*\(\s*['"]fastify['"]\s*\)|\s*fastify\()/
            fastify_instances << $1
          end

          # Detect plugin function declarations
          if line =~ /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\(\s*(?:fastify|app|server)\s*,\s*options\s*\)\s*=>/
            plugin_functions[$1] = true
          end

          # Also detect traditional function syntax for plugins
          if line =~ /(?:function\s+(\w+)\s*\(\s*(?:fastify|app|server)(?:\s*,\s*options)?\s*\)|(?:const|let|var)\s+(\w+)\s*=\s*function\s*\(\s*(?:fastify|app|server)(?:\s*,\s*options)?\s*\))/
            plugin_name = $1 || $2
            plugin_functions[plugin_name] = true if !plugin_name.empty?
          end

          # Detect plugin registration with prefix - more flexible pattern matching
          if line =~ /(\w+)\.register\s*\(\s*(\w+)(?:[^{]*|\s*,\s*)\{[^}]*prefix\s*:\s*['"]([^'"]+)['"]/
            # fastify_var = $1
            plugin_var = $2
            prefix = $3
            if plugin_functions.has_key?(plugin_var) || plugin_var.includes?("Routes")
              route_plugin_prefixes[plugin_var] = prefix
            end
          end
        end

        # Now process the file line by line for endpoints
        current_plugin_var = ""
        inside_plugin_function = false
        plugin_indent_level = 0
        plugin_prefix = ""

        file_content.each_line.with_index do |line, index|
          # Detect plugin function definitions
          if !inside_plugin_function && line =~ /(?:const|let|var)\s+(\w+Routes|\w+)\s*=\s*(?:async\s*)?\(\s*(?:fastify|app|server)\s*,\s*options\s*\)\s*=>/
            function_name = $1
            current_plugin_var = function_name
            inside_plugin_function = true
            plugin_indent_level = line.index("{") || 0
            plugin_prefix = route_plugin_prefixes.fetch(current_plugin_var, "")
          end

          # Check if we're exiting a plugin function
          if inside_plugin_function && line =~ /^\s*\}\s*;?\s*$/
            # Check if the indentation level matches with the function start
            if line.strip == "}" || line.strip == "};"
              current_indent = line.index("}") || 0
              if current_indent <= plugin_indent_level
                inside_plugin_function = false
                current_plugin_var = ""
                plugin_prefix = ""
              end
            end
          end

          # Detect regular routes or routes within plugins
          endpoint = line_to_endpoint(line)
          if endpoint.method != ""
            # Apply plugin prefix if inside a plugin function
            if inside_plugin_function && !plugin_prefix.empty?
              # Handle path joining properly
              if endpoint.url.starts_with?("/") && plugin_prefix.ends_with?("/")
                endpoint.url = "#{plugin_prefix[0..-2]}#{endpoint.url}"
              elsif !endpoint.url.starts_with?("/") && !plugin_prefix.ends_with?("/")
                endpoint.url = "#{plugin_prefix}/#{endpoint.url}"
              else
                endpoint.url = "#{plugin_prefix}#{endpoint.url}"
              end
            end

            details = Details.new(PathInfo.new(path, index + 1))
            endpoint.details = details
            result << endpoint
            last_endpoint = endpoint
          end

          # Get parameters from line
          param = line_to_param(line)
          if param.name != ""
            if last_endpoint.method != ""
              last_endpoint.push_param(param)
            end
          end
        end
      end
    end

    def extract_path_from_route_handler(line : String) : String
      # Path extraction pattern
      match = line.match(/\(\s*['"]([^'"]+)['"]/)
      match ? match[1] : ""
    end

    def line_to_param(line : String) : Param
      # Extract params from request object
      if line.includes?("request.body.") || line.includes?("req.body.")
        param_match = line.match(/(?:request|req)\.body\.(\w+)/)
        param = param_match ? param_match[1] : ""
        return Param.new(param, "", "json") if !param.empty?
      end

      if line.includes?("request.query.") || line.includes?("req.query.")
        param_match = line.match(/(?:request|req)\.query\.(\w+)/)
        param = param_match ? param_match[1] : ""
        return Param.new(param, "", "query") if !param.empty?
      end

      if line.includes?("request.cookies.") || line.includes?("req.cookies.")
        param_match = line.match(/(?:request|req)\.cookies\.(\w+)/)
        param = param_match ? param_match[1] : ""
        return Param.new(param, "", "cookie") if !param.empty?
      end

      # Headers
      if line =~ /(?:request|req)\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/
        return Param.new($1, "", "header")
      end

      if line =~ /(?:request|req)\.header\s*\(\s*['"]([^'"]+)['"]/
        return Param.new($1, "", "header")
      end

      # Path parameters
      if line =~ /(?:request|req)\.params\.(\w+)/
        return Param.new($1, "", "path")
      end

      # Handle destructuring syntax
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:request|req)\.body/
        param_list = $1.split(",").map(&.strip)
        if !param_list.empty?
          # Return the first param, since we can only return one
          return Param.new(param_list.first, "", "json")
        end
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(line : String) : Endpoint
      http_methods = %w[get post put delete patch options head]

      http_methods.each do |method|
        # Match fastify.method patterns
        if line =~ /\b(?:fastify|app|server)\s*\.\s*#{method}\s*\(\s*['"]([^'"]+)['"]/
          path = $1
          return Endpoint.new(path, method.upcase)
        end
      end

      # Handle route method with method as a parameter
      if line =~ /\b(?:fastify|app|server)\s*\.\s*route\s*\(\s*\{/ &&
         (line.includes?("method:") || line.includes?("url:") || line.includes?("path:"))
        # Extract method and path from route configuration object
        method_match = line.match(/method\s*:\s*['"](\w+)['"]/)
        path_match = line.match(/(?:url|path)\s*:\s*['"]([^'"]+)['"]/)

        if method_match && path_match
          method = method_match[1].downcase
          path = path_match[1]
          if http_methods.includes?(method)
            return Endpoint.new(path, method.upcase)
          end
        end
      end

      Endpoint.new("", "")
    end
  end
end
