require "../models/endpoint"
require "../minilexers/js_lexer"
require "../miniparsers/js_parser"

module Noir
  # JSRouteExtractor provides a unified interface for extracting routes from JavaScript files
  class JSRouteExtractor
    def self.extract_routes(file_path : String) : Array(Endpoint)
      return [] of Endpoint unless File.exists?(file_path)

      begin
        content = File.read(file_path)
        parser = JSParser.new(content)
        route_patterns = parser.parse_routes

        endpoints = [] of Endpoint
        route_patterns.each do |pattern|
          # Normalize HTTP method (e.g., DEL -> DELETE)
          normalized_method = normalize_http_method(pattern.method)

          # Handle router.all by expanding to all HTTP methods
          if normalized_method == "ALL"
            all_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
            all_methods.each do |method|
              endpoint = Endpoint.new(pattern.path, method)

              # Add path parameters detected in the URL
              pattern.params.each do |param|
                endpoint.push_param(param)
              end

              # Extract other parameters like body, query, etc. from the content around this route
              extract_params_from_context(content, pattern, endpoint)

              endpoints << endpoint
            end
          else
            endpoint = Endpoint.new(pattern.path, normalized_method)

            # Add path parameters detected in the URL
            pattern.params.each do |param|
              endpoint.push_param(param)
            end

            # Extract other parameters like body, query, etc. from the content around this route
            extract_params_from_context(content, pattern, endpoint)

            endpoints << endpoint
          end
        end

        endpoints
      rescue e
        # If parser fails, return empty array
        [] of Endpoint
      end
    end

    # Normalize HTTP method names to standard format
    def self.normalize_http_method(method : String) : String
      method = method.upcase

      # Standardize HTTP methods
      case method
      when "DEL"
        return "DELETE"
      when "ALL"
        return "ALL" # Keep ALL as-is for special handling
      when "OPTIONS"
        return "OPTIONS"
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"
        return method
      end

      # Return the original (uppercased) method if no specific normalization needed
      method
    end

    def self.extract_params_from_context(content : String, pattern : JSRoutePattern, endpoint : Endpoint)
      # Extract additional parameters from the route handler content
      # Look for the route declaration and then analyze the handler function
      method_name = pattern.method.downcase

      # Create possible method names for both dot notation and bracket notation
      method_variations = [method_name]

      # Handle the case where 'del' might be used instead of 'delete' in the code or vice versa
      if method_name == "delete"
        method_variations << "del"
      elsif method_name == "del"
        method_variations << "delete"
      end

      # Generate all possible route declarations with different syntax patterns
      route_declarations = [] of String
      method_variations.each do |method|
        # Standard method call with single quotes
        route_declarations << "#{method}('#{pattern.path}'"
        # Method call with double quotes
        route_declarations << "#{method}(\"#{pattern.path}\""
        # Method call with template literals
        route_declarations << "#{method}(`#{pattern.path}`"
      end

      # Also handle app.route('/path').method() pattern
      # In this case, search for route('/path')...method(
      route_declarations << "route('#{pattern.path}'"
      route_declarations << "route(\"#{pattern.path}\""
      route_declarations << "route(`#{pattern.path}`"

      # Find the index of any matching route declaration
      idx = nil
      found_declaration = ""
      route_declarations.each do |declaration|
        found_idx = content.index(declaration)
        if found_idx
          idx = found_idx
          found_declaration = declaration
          break
        end
      end

      return unless idx

      # If we found a route() declaration, we need to find the specific .method() call after it
      if found_declaration.starts_with?("route(")
        # Look for the .method( pattern after the route declaration
        search_start = idx
        method_variations.each do |method|
          method_idx = content.index(".#{method}(", search_start)
          if method_idx && method_idx > idx && (method_idx - idx) < 200
            idx = method_idx
            break
          end
        end
      end

      # Find the opening brace of the handler function
      open_brace_idx = content.index("{", idx)
      return unless open_brace_idx

      # Extract the handler function body
      # (This is a simplified approach - a more robust approach would count braces)
      close_brace_idx = find_matching_brace(content, open_brace_idx)
      return unless close_brace_idx

      handler_body = content[open_brace_idx..close_brace_idx]

      # Now analyze the handler body for req.body, req.query, etc.
      extract_body_params(handler_body, endpoint)
      extract_query_params(handler_body, endpoint)
      extract_header_params(handler_body, endpoint)
      extract_cookie_params(handler_body, endpoint)
    end

    def self.find_matching_brace(content : String, open_brace_idx : Int32) : Int32?
      brace_count = 1
      idx = open_brace_idx + 1

      while idx < content.size && brace_count > 0
        case content[idx]
        when '{'
          brace_count += 1
        when '}'
          brace_count -= 1
        end
        idx += 1

        # Return the position of the matching closing brace
        return idx - 1 if brace_count == 0
      end

      # No matching brace found
      nil
    end

    def self.extract_body_params(handler_body : String, endpoint : Endpoint)
      # Look for req.body.X or const/let/var { X } = req.body
      # First check the destructuring pattern
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\.body/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = param.split("=").first.strip
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      # Check direct property access: req.body.X
      handler_body.scan(/(?:req|request)\.body\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "json"))
        end
      end

      # Check array access: req.body['X'] or req.body["X"]
      handler_body.scan(/(?:req|request)\.body\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "json"))
        end
      end
    end

    def self.extract_query_params(handler_body : String, endpoint : Endpoint)
      # Look for destructuring: const/let/var { X } = req.query
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\.query/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = param.split("=").first.strip
            endpoint.push_param(Param.new(clean_param, "", "query")) unless clean_param.empty?
          end
        end
      end

      # Look for req.query.X
      handler_body.scan(/(?:req|request)\.query\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end
    end

    def self.extract_header_params(handler_body : String, endpoint : Endpoint)
      # Look for req.headers['X'] or req.header('X') (Express-style)
      handler_body.scan(/(?:req|request)\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      handler_body.scan(/(?:req|request)\.headers\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      handler_body.scan(/(?:req|request)\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      # Koa-style headers: ctx.headers['X'], ctx.header['X'], ctx.get('X')
      handler_body.scan(/ctx\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      handler_body.scan(/ctx\.header\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      handler_body.scan(/ctx\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end
    end

    def self.extract_cookie_params(handler_body : String, endpoint : Endpoint)
      # Look for req.cookies.X (Express-style)
      handler_body.scan(/(?:req|request)\.cookies\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "cookie"))
        end
      end

      # Koa-style cookies: ctx.cookies.get('X')
      handler_body.scan(/ctx\.cookies\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "cookie"))
        end
      end
    end

    # Extract static path declarations from JavaScript content
    # Returns array of hashes with static_path (URL prefix) and file_path (directory)
    def self.extract_static_paths(content : String) : Array(Hash(String, String))
      static_paths = [] of Hash(String, String)

      # Express patterns:
      # app.use('/static', express.static('public'))
      # app.use(express.static('public'))
      # router.use('/static', express.static('public'))
      content.scan(/(?:app|router|\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:express\.)?static\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => match[1],
            "file_path"   => match[2],
          }
        end
      end

      # app.use(express.static('public')) - no prefix, serves at root
      content.scan(/(?:app|router|\w+)\.use\s*\(\s*(?:express\.)?static\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size >= 1
          static_paths << {
            "static_path" => "/",
            "file_path"   => match[1],
          }
        end
      end

      # Koa patterns with koa-static:
      # app.use(serve('public'))
      # app.use(serve('./static'))
      content.scan(/(?:app|router|\w+)\.use\s*\(\s*serve\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size >= 1
          static_paths << {
            "static_path" => "/",
            "file_path"   => match[1],
          }
        end
      end

      # Koa patterns with koa-mount + koa-static:
      # app.use(mount('/static', serve('public')))
      content.scan(/(?:app|router|\w+)\.use\s*\(\s*mount\s*\(\s*['"]([^'"]+)['"]\s*,\s*serve\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => match[1],
            "file_path"   => match[2],
          }
        end
      end

      # Fastify patterns:
      # fastify.register(require('@fastify/static'), { root: path.join(__dirname, 'public'), prefix: '/public/' })
      content.scan(/(?:fastify|app|server)\.register\s*\([^{]*\{[^}]*root\s*:\s*[^,}]*['"]([^'"]+)['"][^}]*prefix\s*:\s*['"]([^'"]+)['"]/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => match[2],
            "file_path"   => match[1],
          }
        end
      end

      # Also try reverse order (prefix first, then root)
      content.scan(/(?:fastify|app|server)\.register\s*\([^{]*\{[^}]*prefix\s*:\s*['"]([^'"]+)['"][^}]*root\s*:\s*[^,}]*['"]([^'"]+)['"]/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => match[1],
            "file_path"   => match[2],
          }
        end
      end

      # Restify patterns:
      # server.get(/\/public\/.*/, restify.plugins.serveStatic({directory: './public'}))
      # Try to extract the path from the regex pattern first
      content.scan(/(?:server|app)\.(?:get|use)\s*\(\s*\/\\?\/([^\/]+)\/[^,]*,\s*restify\.plugins\.serveStatic\s*\(\s*\{[^}]*directory\s*:\s*['"]([^'"]+)['"]/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => "/#{match[1]}",
            "file_path"   => match[2],
          }
        end
      end

      # Fallback: If no path in regex, use directory name as path
      content.scan(/(?:server|app)\.(?:get|use)\s*\([^,]*,\s*restify\.plugins\.serveStatic\s*\(\s*\{[^}]*directory\s*:\s*['"]\.?\/?([\w-]+)['"]\s*\}/) do |match|
        if match.size >= 1
          dir_name = match[1]
          # Check if this is already captured
          unless static_paths.any? { |s| s["file_path"].includes?(dir_name) }
            static_paths << {
              "static_path" => "/#{dir_name}",
              "file_path"   => match[1],
            }
          end
        end
      end

      # NestJS patterns typically use ServeStaticModule in app.module.ts
      # ServeStaticModule.forRoot({ rootPath: join(__dirname, '..', 'public'), serveRoot: '/static' })
      content.scan(/ServeStaticModule\.forRoot\s*\(\s*\{[^}]*rootPath\s*:[^,}]*['"]([^'"]+)['"][^}]*serveRoot\s*:\s*['"]([^'"]+)['"]/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => match[2],
            "file_path"   => match[1],
          }
        end
      end

      # Also try reverse order for NestJS
      content.scan(/ServeStaticModule\.forRoot\s*\(\s*\{[^}]*serveRoot\s*:\s*['"]([^'"]+)['"][^}]*rootPath\s*:[^,}]*['"]([^'"]+)['"]/) do |match|
        if match.size >= 2
          static_paths << {
            "static_path" => match[1],
            "file_path"   => match[2],
          }
        end
      end

      static_paths
    end
  end
end
