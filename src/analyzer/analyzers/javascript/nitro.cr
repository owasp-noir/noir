require "../../engines/javascript_engine"

module Analyzer::Javascript
  class Nitro < JavascriptEngine
    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_js_scan([".js", ".ts", ".mjs", ".mts"]) do |path|
        # Focus on routes/ directory for Nitro
        next unless path.includes?("/routes/")
        analyze_nitro_file(path, result, mutex)
      end

      result
    end

    private def analyze_nitro_file(path : String, result : Array(Endpoint), mutex : Mutex)
      # Extract endpoint from file path
      # routes/hello.ts -> /hello
      # routes/users/[id].ts -> /users/:id
      # routes/users.get.ts -> /users (GET only)
      # routes/api/items.ts -> /api/items

      base_path_idx = path.index("/routes/")
      return if base_path_idx.nil?

      # Get the path after /routes/
      relative_path = path[(base_path_idx + "/routes/".size)..-1]

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

      # Convert [...slug] catch-all routes
      relative_path = relative_path.gsub(/\[\.\.\.(\w+)\]/, "*")

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
              next if ["toString", "valueOf", "constructor"].includes?(param_name)
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
          end

          # Extract body parameters from readBody
          if content.includes?("readBody(event)") || content.includes?("await readBody")
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
