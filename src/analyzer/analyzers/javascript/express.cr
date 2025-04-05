require "../../../models/analyzer"

module Analyzer::Javascript
  class Express < Analyzer
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
                  # Fix: use any? with an array instead of multiple arguments to ends_with?
                  next unless [".js", ".ts", ".jsx", ".tsx"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      last_endpoint = Endpoint.new("", "")
                      current_router_base = ""
                      router_detected = false
                      file_content = file.gets_to_end

                      # First analyze file for router imports and declarations
                      file_content.each_line do |line|
                        # Detect Express router imports and initialization
                        if line.includes?("require('express')") || line.includes?("require(\"express\")") ||
                           line.includes?("from 'express'") || line.includes?("from \"express\"")
                          router_detected = true
                        end

                        # Detect router initialization
                        if line.includes?("Router()") || line.includes?("express.Router()") ||
                           line.includes?("Router();") || line.includes?("express.Router();")
                          router_detected = true
                        end
                      end

                      # Now process the file line by line for endpoints
                      file_content.each_line.with_index do |line, index|
                        # Detect router base path
                        if line =~ /\.use\s*\(\s*['"]([^'"]+)['"]/
                          current_router_base = $1
                        end

                        # Get endpoint from line
                        endpoint = line_to_endpoint(line, router_detected)
                        if endpoint.method != ""
                          # If we have a router base path and the endpoint doesn't start with it
                          if !current_router_base.empty? && !endpoint.url.starts_with?("/")
                            endpoint.url = "#{current_router_base}/#{endpoint.url}"
                          elsif !current_router_base.empty? && endpoint.url != "/" && !endpoint.url.starts_with?(current_router_base)
                            endpoint.url = "#{current_router_base}#{endpoint.url}"
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
        logger.debug "Error in Express analyzer: #{e.message}"
      end

      result
    end

    def extract_path_from_route_handler(line : String) : String
      # More robust path extraction handling different quote styles
      match = line.match(/\(\s*['"]([^'"]+)['"]/)
      match ? match[1] : ""
    end

    def line_to_param(line : String) : Param
      # Extract params from request object
      if line.includes? "req.body."
        param = line.split("req.body.")[1].split(/[^\w\d]/)[0]
        return Param.new(param, "", "json")
      end

      if line.includes? "req.query."
        param = line.split("req.query.")[1].split(/[^\w\d]/)[0]
        return Param.new(param, "", "query")
      end

      if line.includes? "req.cookies."
        param = line.split("req.cookies.")[1].split(/[^\w\d]/)[0]
        return Param.new(param, "", "cookie")
      end

      # More patterns for param extraction
      if line =~ /req\.header\s*\(\s*['"]([^'"]+)['"]/
        return Param.new($1, "", "header")
      end

      if line =~ /req\.headers\s*(?:\[\s*['"]([^'"]+)['"]\s*\]|\.\s*(\w+))/
        param_name = $1 || $2
        return Param.new(param_name, "", "header")
      end

      # Path parameters
      if line =~ /req\.params\.(\w+)/
        return Param.new($1, "", "path")
      end

      # Handle destructuring syntax
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*req\.body/
        param_list = $1.split(",").map(&.strip)
        if !param_list.empty?
          # Return first param to avoid empty result
          param_name = param_list.first
          return Param.new(param_name, "", "json")
        end
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(line : String, router_detected : Bool = false) : Endpoint
      http_methods = %w(get post put delete patch options head)

      http_methods.each do |method|
        # Match both app.method and router.method patterns
        if line =~ /\b(?:app|router|route|r|Router)\s*\.\s*#{method}\s*\(\s*['"]([^'"]+)['"]/ ||
           line =~ /\.\s*#{method}\s*\(\s*['"]([^'"]+)['"]/
          path = $1
          return Endpoint.new(path, method.upcase)
        end
      end

      # Handle route method with method as a parameter
      if line =~ /\b(?:app|router|route|r|Router)\s*\.\s*route\s*\(\s*['"]([^'"]+)['"].*?\.(?:get|post|put|delete|patch|options|head)\s*\(/
        path = $1
        method = line.scan(/\.(?:get|post|put|delete|patch|options|head)\s*\(/)[0][0].gsub(/[\.\s\(]/, "")
        return Endpoint.new(path, method.upcase)
      end

      Endpoint.new("", "")
    end
  end
end
