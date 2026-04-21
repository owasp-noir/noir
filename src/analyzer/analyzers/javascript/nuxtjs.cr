require "../../engines/javascript_engine"

module Analyzer::Javascript
  class Nuxtjs < JavascriptEngine
    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_file_scan([".js", ".ts", ".mjs", ".mts"]) do |path|
        # Focus on server/api and server/routes directories for Nuxt 3
        next unless path.includes?("/server/api/") || path.includes?("/server/routes/")
        analyze_nuxt_file(path, result, mutex)
      end

      result
    end

    private def analyze_nuxt_file(path : String, result : Array(Endpoint), mutex : Mutex)
      # Extract endpoint from file path
      # server/api/hello.ts -> /api/hello
      # server/api/users/[id].ts -> /api/users/:id
      # server/api/users.get.ts -> /api/users (GET only)
      # server/routes/custom.ts -> /custom

      relative_path = path
      base_path_idx = path.index("/server/api/")
      is_api_route = true

      if base_path_idx.nil?
        base_path_idx = path.index("/server/routes/")
        is_api_route = false
      end

      return if base_path_idx.nil?

      # Get the path after /server/api/ or /server/routes/
      if is_api_route
        relative_path = path[(base_path_idx + "/server/api/".size)..-1]
      else
        relative_path = path[(base_path_idx + "/server/routes/".size)..-1]
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

      # Build the URL
      url = if is_api_route
              "/api/#{relative_path}"
            else
              "/#{relative_path}"
            end

      # Clean up double slashes
      url = url.gsub("//", "/")

      # Handle index routes
      url = url.gsub(/\/index$/, "")
      url = "/" if url.empty?

      # Determine HTTP methods
      methods = specific_method ? [specific_method] : ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

      # Read file content to extract parameters
      begin
        content = File.read(path, encoding: "utf-8", invalid: :skip)

        methods.each do |method|
          endpoint = Endpoint.new(url, method)
          details = Details.new(PathInfo.new(path, 1))
          endpoint.details = details

          # Extract path parameters from URL
          url.scan(/:(\w+)/) do |m|
            if m.size > 0
              param = Param.new(m[1], "", "path")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
            end
          end

          # Extract query parameters from getQuery or useQuery
          # Pattern 1: Direct access - getQuery(event).param
          content.scan(/(?:getQuery|useQuery)\s*\(\s*event\s*\)\.(\w+)/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "query")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
          end

          # Pattern 2: Variable assignment - const query = getQuery(event); query.param
          if content.match(/(?:const|let|var)\s+(\w+)\s*=\s*(?:getQuery|useQuery)\s*\(\s*event\s*\)/)
            query_var = $1
            content.scan(/#{Regex.escape(query_var)}\.(\w+)/) do |m|
              param_name = m[1]
              # Skip common non-parameter properties like 'toString', 'valueOf', etc.
              next if ["toString", "valueOf", "constructor"].includes?(param_name)
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
          end

          # Extract body parameters from readBody
          if content.includes?("readBody(event)") || content.includes?("await readBody")
            # Try to extract body field access patterns
            content.scan(/(?:body|data)\.(\w+)/) do |m|
              param_name = m[1]
              param = Param.new(param_name, "", "body")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
            end
          end

          # Extract header parameters from getHeader or getHeaders
          content.scan(/getHeader\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            header_name = m[1]
            param = Param.new(header_name, "", "header")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
          end

          # Extract cookie parameters from getCookie
          content.scan(/getCookie\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            cookie_name = m[1]
            param = Param.new(cookie_name, "", "cookie")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
          end

          mutex.synchronize do
            existing_idx = result.index { |e| e.url == url && e.method == method }
            if existing_idx
              # Method-specific files take precedence over generic handlers
              if specific_method
                result[existing_idx] = endpoint
              end
            else
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
