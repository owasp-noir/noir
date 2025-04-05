require "../../../models/analyzer"

module Analyzer::Javascript
  class Restify < Analyzer
    def analyze
      # Source Analysis
      channel = Channel(String).new
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
                  next unless [".js", ".ts", ".jsx", ".tsx"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      last_endpoint = Endpoint.new("", "")
                      server_var_names = [] of String
                      router_var_names = [] of String
                      router_base_paths = {} of String => String
                      current_router_base = ""
                      current_router_var = ""
                      file_content = file.gets_to_end

                      # First scan for server and router variable declarations
                      file_content.each_line do |line|
                        # Detect Restify server creation
                        if line =~ /(?:const|let|var)\s+(\w+)\s*=\s*restify\.createServer/
                          server_var_names << $1
                        end

                        # Detect router initialization
                        if line =~ /(?:const|let|var)\s+(\w+)\s*=\s*(?:new\s+)?(?:restify\.)?Router/
                          router_var_names << $1
                          current_router_var = $1
                        end

                        # Detect router mounting with use
                        if line =~ /\.use\s*\(\s*['"]([^'"]+)['"]/
                          current_router_base = $1
                        end

                        # Detect applyRoutes with base path
                        if line =~ /(\w+)\.applyRoutes\s*\(\s*\w+\s*,\s*['"]([^'"]+)['"]/
                          router_var = $1
                          base_path = $2
                          router_base_paths[router_var] = base_path
                        end
                      end

                      # Now process the file line by line for endpoints
                      file_content.each_line.with_index do |line, index|
                        endpoint = line_to_endpoint(line, server_var_names, router_var_names)

                        if endpoint.method != ""
                          # Store the variable this endpoint is associated with
                          endpoint_var = extract_endpoint_var(line)

                          # Apply base paths from applyRoutes if applicable
                          if !endpoint_var.empty? && router_base_paths.has_key?(endpoint_var)
                            base_path = router_base_paths[endpoint_var]
                            # Ensure proper path joining
                            if endpoint.url.starts_with?("/") && base_path.ends_with?("/")
                              endpoint.url = "#{base_path[0..-2]}#{endpoint.url}"
                            elsif !endpoint.url.starts_with?("/") && !base_path.ends_with?("/")
                              endpoint.url = "#{base_path}/#{endpoint.url}"
                            else
                              endpoint.url = "#{base_path}#{endpoint.url}"
                            end
                            # Apply current router base if this is a generic router endpoint
                          elsif !current_router_base.empty? && !endpoint.url.starts_with?("/")
                            endpoint.url = "#{current_router_base}/#{endpoint.url}"
                          elsif !current_router_base.empty? && endpoint.url != "/" && !endpoint.url.starts_with?(current_router_base)
                            endpoint.url = "#{current_router_base}#{endpoint.url}"
                          end

                          details = Details.new(PathInfo.new(path, index + 1))
                          endpoint.details = details
                          result << endpoint
                          last_endpoint = endpoint
                        end

                        param = line_to_param(line)
                        if param.name != ""
                          if last_endpoint.method != ""
                            last_endpoint.push_param(param)
                          end
                        end
                      end
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
        logger.debug "Error in Restify analyzer: #{e.message}"
      end

      result
    end

    def extract_endpoint_var(line : String) : String
      # Extract the variable name from a route definition line
      # For example, from "apiRouter.get('/products', ..." extract "apiRouter"
      match = line.match(/^\s*(\w+)\.\s*(?:get|post|put|delete|patch|options|head)/)
      match ? match[1] : ""
    end

    def extract_path(line : String) : String
      # Extract path from route definition, handling different quote styles
      match = line.match(/\(\s*['"]([^'"]+)['"]/)
      match ? match[1] : ""
    end

    def line_to_param(line : String) : Param
      # Extract request body parameters
      if line.includes? "req.body."
        param = line.split("req.body.")[1].split(/[^\w\d]/)[0]
        return Param.new(param, "", "json")
      end

      # Extract query parameters
      if line.includes? "req.query."
        param = line.split("req.query.")[1].split(/[^\w\d]/)[0]
        return Param.new(param, "", "query")
      end

      # Extract cookie parameters
      if line.includes? "req.cookies."
        param = line.split("req.cookies.")[1].split(/[^\w\d]/)[0]
        return Param.new(param, "", "cookie")
      end

      # Extract header parameters - various syntax forms
      if line =~ /req\.header\s*\(\s*['"]([^'"]+)['"]/
        return Param.new($1, "", "header")
      end

      if line =~ /req\.headers\s*(?:\[\s*['"]([^'"]+)['"]\s*\]|\.\s*(\w+))/
        param_name = $1 || $2
        return Param.new(param_name, "", "header")
      end

      # Extract path parameters
      if line =~ /req\.params\.(\w+)/
        return Param.new($1, "", "path")
      end

      # Handle destructuring syntax
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*req\.body/
        params = $1.split(",").map(&.strip)
        if !params.empty?
          # Return first param to avoid empty result
          param_name = params.first
          return Param.new(param_name, "", "json")
        end
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(line : String, server_vars = [] of String, router_vars = [] of String) : Endpoint
      http_methods = %w(get post put delete patch options head)

      # Build a regex pattern that includes all server and router variable names
      var_pattern = (server_vars + router_vars).join("|")
      var_pattern = var_pattern.empty? ? "server|router" : var_pattern

      http_methods.each do |method|
        # Match server.method, router.method patterns
        if line =~ /\b(?:#{var_pattern})\s*\.\s*#{method}\s*\(\s*['"]([^'"]+)['"]/
          path = $1
          return Endpoint.new(path, method.upcase)
        end

        # Generic patterns with dot notation
        if line =~ /\.\s*#{method}\s*\(\s*['"]([^'"]+)['"]/
          path = $1
          return Endpoint.new(path, method.upcase)
        end
      end

      # Handle route method with HTTP method as parameter
      if line =~ /\b(?:#{var_pattern})\s*\.\s*route\s*\(\s*['"]([^'"]+)['"].*?\.(?:get|post|put|delete|patch|options|head)\s*\(/
        path = $1
        method = line.scan(/\.(?:get|post|put|delete|patch|options|head)\s*\(/)[0][0].gsub(/[\.\s\(]/, "")
        return Endpoint.new(path, method.upcase)
      end

      Endpoint.new("", "")
    end
  end
end
