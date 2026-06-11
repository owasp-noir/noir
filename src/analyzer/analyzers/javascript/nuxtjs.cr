require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Nuxtjs < JavascriptEngine
    EXTENSIONS = [".js", ".ts", ".mjs", ".mts"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      parallel_file_scan(EXTENSIONS) do |path|
        # Focus on server/api and server/routes directories for Nuxt 3
        next unless path.includes?("/server/api/") || path.includes?("/server/routes/")
        # Skip `*.test.ts` / `*.spec.ts` siblings — they don't
        # define Nuxt event handlers, just exercise neighbors.
        next if path.includes?(".test.") || path.includes?(".spec.")
        # Skip mini-Nuxt fixtures used to test the framework itself.
        # nuxt/nuxt parks 18 phantom endpoints under
        # `test/fixtures/<scenario>/server/api/` — each fixture is a
        # full Nuxt project the test suite spins up, but none of the
        # routes serve real traffic.
        next if path.includes?("/test/fixtures/") || path.includes?("/tests/fixtures/")
        next if path.includes?("/__tests__/") || path.includes?("/__mocks__/")
        analyze_nuxt_file(path, result, mutex, include_callee)
      end

      result
    end

    private def analyze_nuxt_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
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
      relative_path = strip_extension(relative_path)

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

      # Convert Nuxt dynamic route segments:
      #   [id] -> :id, [...slug] / [[...slug]] -> :slug
      relative_path = convert_nuxt_segments(relative_path)

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

      # Determine HTTP methods. With a method-suffixed file name
      # (`users.get.ts`) Nuxt only handles that verb. Without one
      # the file's `defineEventHandler` runs for any incoming
      # method, so emit a single `ANY` endpoint instead of seven
      # near-duplicate rows — matching how Echo/Mux/etc. surface
      # method-agnostic registrations.
      methods = specific_method ? [specific_method] : ["ANY"]

      # Read file content to extract parameters
      begin
        content = read_file_content(path)
        sanitized = Noir::JSRouteExtractor.strip_js_comments(content)
        callees = include_callee ? Noir::JSCalleeExtractor.callees_for_default_event_handler(content, path, language: javascript_source_language(path)) : [] of Noir::JSCalleeExtractor::Entry

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
          sanitized.scan(/(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)\.(\w+)/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "query")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
          end
          sanitized.scan(/(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "query")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
          end
          sanitized.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*(?:await\s+)?(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |m|
            extract_destructure_params(m[1]).each do |param_name|
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
          end

          # Pattern 2: Variable assignment - const query = getQuery(event); query.param
          sanitized.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |var_match|
            query_var = var_match[1]
            sanitized.scan(cached_regex("nuxtjs:query_dot:#{query_var}") { /#{Regex.escape(query_var)}\.(\w+)/ }) do |m|
              param_name = m[1]
              # Skip common non-parameter properties like 'toString', 'valueOf', etc.
              next if ["toString", "valueOf", "constructor"].includes?(param_name)
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
            sanitized.scan(cached_regex("nuxtjs:query_bracket:#{query_var}") { /#{Regex.escape(query_var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/ }) do |m|
              param_name = m[1]
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
          end

          # Extract body parameters from readBody
          if sanitized.includes?("readBody") || sanitized.includes?("readValidatedBody")
            # Try to extract body field access patterns
            sanitized.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*(?:await\s+)?(?:readBody|readValidatedBody)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |m|
              extract_destructure_params(m[1]).each do |param_name|
                param = Param.new(param_name, "", "body")
                endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
              end
            end
            body_vars = ["body", "data"]
            sanitized.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:readBody|readValidatedBody)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |m|
              body_vars << m[1] unless body_vars.includes?(m[1])
            end
            body_vars.each do |body_var|
              sanitized.scan(cached_regex("nuxtjs:var_dot:#{body_var}") { /\b#{Regex.escape(body_var)}\.(\w+)/ }) do |m|
                param_name = m[1]
                param = Param.new(param_name, "", "body")
                endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
              end
              sanitized.scan(cached_regex("nuxtjs:var_bracket:#{body_var}") { /\b#{Regex.escape(body_var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/ }) do |m|
                param_name = m[1]
                param = Param.new(param_name, "", "body")
                endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
              end
            end
          end

          # Extract header parameters from getHeader or getHeaders
          sanitized.scan(/(?:getHeader|getRequestHeader)\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            header_name = m[1]
            param = Param.new(header_name, "", "header")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
          end
          sanitized.scan(/getHeaders\s*\(\s*event\s*\)\.(\w+)/) do |m|
            header_name = m[1]
            param = Param.new(header_name, "", "header")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
          end
          sanitized.scan(/(?:const|let|var)\s+(\w+)\s*=\s*getHeaders\s*\(\s*event\s*\)/) do |m|
            headers_var = m[1]
            sanitized.scan(cached_regex("nuxtjs:var_dot:#{headers_var}") { /\b#{Regex.escape(headers_var)}\.(\w+)/ }) do |mm|
              header_name = mm[1]
              param = Param.new(header_name, "", "header")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
            end
            sanitized.scan(cached_regex("nuxtjs:var_bracket:#{headers_var}") { /\b#{Regex.escape(headers_var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/ }) do |mm|
              header_name = mm[1]
              param = Param.new(header_name, "", "header")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
            end
          end

          # Extract cookie parameters from getCookie
          sanitized.scan(/getCookie\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            cookie_name = m[1]
            param = Param.new(cookie_name, "", "cookie")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
          end
          sanitized.scan(/getRouterParam\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "path")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          end

          attach_js_callees(endpoint, callees) if include_callee

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

    private def strip_extension(path : String) : String
      EXTENSIONS.each do |ext|
        return path[0..(path.size - ext.size - 1)] if path.ends_with?(ext)
      end
      path
    end

    private def convert_nuxt_segments(path : String) : String
      path.split("/").map do |segment|
        if m = segment.match(/^\[\[\.\.\.(\w+)\]\]$/)
          ":#{m[1]}"
        elsif m = segment.match(/^\[\.\.\.(\w+)\]$/)
          ":#{m[1]}"
        elsif m = segment.match(/^\[(\w+)\]$/)
          ":#{m[1]}"
        else
          segment
        end
      end.join("/")
    end

    private def extract_destructure_params(destructure : String) : Array(String)
      return [] of String if destructure.includes?("{") || destructure.includes?("(") ||
                             destructure.includes?("<")

      destructure.split(",").map do |part|
        clean = part.split("=").first.strip
        clean = clean.lchop("...").strip
        clean = clean.split(":").first.strip if clean.includes?(":")
        clean = clean[1..-2] if clean.size >= 2 &&
                                ((clean.starts_with?("'") && clean.ends_with?("'")) ||
                                (clean.starts_with?("\"") && clean.ends_with?("\"")))
        clean
      end.select(&.match(/^[A-Za-z_$][\w$-]*$/))
    end
  end
end
