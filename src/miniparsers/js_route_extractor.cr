require "../models/endpoint"
require "../minilexers/js_lexer"
require "../miniparsers/js_parser"
require "../models/code_locator"
require "../utils/url_path"
require "../analyzer/analyzers/javascript/express_constants"

module Noir
  # JSRouteExtractor provides a unified interface for extracting routes from JavaScript files
  class JSRouteExtractor
    # Import constants for key generation
    ROUTER_PREFIX_KEY = Analyzer::Javascript::ExpressConstants::ROUTER_PREFIX_KEY

    def self.extract_routes(file_path : String, content : String? = nil, debug : Bool = false) : Array(Endpoint)
      return [] of Endpoint unless File.exists?(file_path)

      begin
        content = content || File.read(file_path, encoding: "utf-8", invalid: :skip)
        parser = JSParser.new(content)
        route_patterns = parser.parse_routes

        if debug && parser.hit_max_iterations?
          STDERR.puts "Warning: Maximum iterations reached in JS parser, parsing may be incomplete"
        end

        # Check if this file has a router prefix from cross-file mounting
        locator = CodeLocator.instance

        # Normalize file path to absolute path for consistent lookup
        absolute_file_path = File.expand_path(file_path)
        lookup_key = Analyzer::Javascript::ExpressConstants.file_key(absolute_file_path)
        # Use all() since routers can be mounted at multiple prefixes
        file_prefixes = locator.all(lookup_key)

        # Build function ranges to support function-scoped router prefixes
        function_ranges = [] of Tuple(String, Int32, Int32)
        function_names = Set(String).new
        function_patterns = {
          /function\s+(\w+)\s*\(/ => :function,
          /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function\b/ => :function,
          /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)\s*=>/ => :arrow,
          /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\w+\s*=>/ => :arrow,
        }
        function_patterns.each do |pattern, kind|
          content.scan(pattern) do |m|
            next unless m.size >= 2
            func_name = m[1]
            match_start = m.begin(0)
            next unless match_start

            open_brace_idx = nil
            if kind == :arrow
              arrow_idx = content.index("=>", match_start)
              next unless arrow_idx
              open_brace_idx = content.index("{", arrow_idx + 2)
            else
              param_start = content.index("(", match_start)
              next unless param_start
              param_end = find_matching_paren(content, param_start) || param_start
              open_brace_idx = content.index("{", param_end + 1)
            end

            next unless open_brace_idx
            close_brace_idx = find_matching_brace(content, open_brace_idx)
            next unless close_brace_idx
            function_ranges << {func_name, open_brace_idx, close_brace_idx}
            function_names.add(func_name)
          end
        end

        # Build internal mount relationships: parent function -> child function with prefix
        internal_mounts = [] of Tuple(String, String, String)
        function_ranges.each do |func_name, start_idx, end_idx|
          body = content[start_idx..end_idx]
          body.scan(/\b\w+\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)\s*(?:\(\s*\))?/) do |m|
            if m.size >= 3
              prefix = m[1]
              child_func = m[2]
              if function_names.includes?(child_func)
                internal_mounts << {func_name, child_func, prefix}
              end
            end
          end
        end

        # Seed function-specific prefixes from CodeLocator
        prefixes_by_function = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
        function_names.each do |func_name|
          func_key = "express_router_prefix:#{absolute_file_path}:#{func_name}"
          values = locator.all(func_key)
          if values.size > 0
            values.each do |prefix|
              prefixes_by_function[func_name] << prefix unless prefix.empty?
            end
          else
            value = locator.get(func_key)
            if value.is_a?(String) && !value.empty?
              prefixes_by_function[func_name] << value
            end
          end
        end

        # Propagate prefixes through internal mounts with max iteration protection
        changed = true
        max_iterations = 100 # Prevent infinite loops in case of cyclic references
        iterations = 0
        while changed && iterations < max_iterations
          changed = false
          iterations += 1
          internal_mounts.each do |parent, child, mount_prefix|
            parent_prefixes = prefixes_by_function[parent]
            if parent_prefixes.empty? && !file_prefixes.empty?
              parent_prefixes = file_prefixes
            end
            parent_prefixes.each do |p|
              combined = URLPath.join(p, mount_prefix)
              unless prefixes_by_function[child].includes?(combined)
                prefixes_by_function[child] << combined
                changed = true
              end
            end
          end
        end

        endpoints = [] of Endpoint
        route_patterns.each do |pattern|
          # Apply cross-file router prefix if present (function-scoped first)
          prefixes = [] of String
          if pattern.start_pos >= 0
            # Find all functions containing this route, sorted by span (innermost first)
            containing_functions = [] of Tuple(String, Int32)
            function_ranges.each do |func_name, start_idx, end_idx|
              if start_idx <= pattern.start_pos && pattern.start_pos <= end_idx
                span = end_idx - start_idx
                containing_functions << {func_name, span}
              end
            end
            containing_functions.sort_by! { |_, span| span }

            # Walk outward through enclosing functions until we find one with prefixes
            containing_functions.each do |func_name, _|
              func_prefixes = prefixes_by_function[func_name]
              unless func_prefixes.empty?
                prefixes = func_prefixes
                break
              end
            end
          end
          if prefixes.empty? && !file_prefixes.empty?
            prefixes = file_prefixes
          end
          prefixes = [""] if prefixes.empty?

          # Normalize HTTP method (e.g., DEL -> DELETE)
          normalized_method = normalize_http_method(pattern.method)

          # Handle router.all by expanding to all HTTP methods
          prefixes.each do |prefix|
            path_with_prefix = prefix.empty? ? pattern.path : URLPath.join(prefix, pattern.path)

            if normalized_method == "ALL"
              all_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
              all_methods.each do |method|
                endpoint = Endpoint.new(path_with_prefix, method)

                # Add path parameters detected in the URL
                pattern.params.each do |param|
                  endpoint.push_param(param)
                end

                # Extract other parameters like body, query, etc. from the content around this route
                extract_params_from_context(content, pattern, endpoint)

                endpoints << endpoint
              end
            else
              endpoint = Endpoint.new(path_with_prefix, normalized_method)

              # Add path parameters detected in the URL
              pattern.params.each do |param|
                endpoint.push_param(param)
              end

              # Extract other parameters like body, query, etc. from the content around this route
              extract_params_from_context(content, pattern, endpoint)

              endpoints << endpoint
            end
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
      lookup_path = pattern.raw_path
      method_variations.each do |method|
        # Standard method call with single quotes
        route_declarations << "#{method}('#{lookup_path}'"
        # Method call with double quotes
        route_declarations << "#{method}(\"#{lookup_path}\""
        # Method call with template literals
        route_declarations << "#{method}(`#{lookup_path}`"
      end

      # Also handle app.route('/path').method() pattern
      # In this case, search for route('/path')...method(
      route_declarations << "route('#{lookup_path}'"
      route_declarations << "route(\"#{lookup_path}\""
      route_declarations << "route(`#{lookup_path}`"

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

      # Find the bounds of the method call arguments to keep the search scoped
      open_paren_idx = content.index("(", idx)
      return unless open_paren_idx
      close_paren_idx = find_matching_paren(content, open_paren_idx)
      return unless close_paren_idx

      args_start = open_paren_idx + 1
      args_end = close_paren_idx - 1
      return if args_end < args_start

      args_slice = content[args_start..args_end]
      function_idx = args_slice.rindex(/\bfunction\b/)
      arrow_idx = args_slice.rindex("=>")

      anchor_idx = nil
      anchor_kind = :function
      if function_idx && arrow_idx
        if function_idx > arrow_idx
          anchor_idx = function_idx
          anchor_kind = :function
        else
          anchor_idx = arrow_idx
          anchor_kind = :arrow
        end
      elsif function_idx
        anchor_idx = function_idx
        anchor_kind = :function
      elsif arrow_idx
        anchor_idx = arrow_idx
        anchor_kind = :arrow
      end

      return unless anchor_idx

      anchor_abs = args_start + anchor_idx
      open_brace_idx = content.index("{", anchor_abs)
      return unless open_brace_idx && open_brace_idx < close_paren_idx

      # Avoid treating concise arrow returning object literals as a block body.
      if anchor_kind == :arrow
        prev = open_brace_idx - 1
        while prev > anchor_abs && content[prev].whitespace?
          prev -= 1
        end
        return if prev >= anchor_abs && content[prev] == '('
      end

      # Extract the handler function body
      # (This is a simplified approach - a more robust approach would count braces)
      close_brace_idx = find_matching_brace(content, open_brace_idx)
      return unless close_brace_idx && close_brace_idx < close_paren_idx

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

    def self.find_matching_paren(content : String, open_paren_idx : Int32) : Int32?
      paren_count = 1
      idx = open_paren_idx + 1

      while idx < content.size && paren_count > 0
        char = content[idx]

        # Skip single-line comments
        if char == '/' && idx + 1 < content.size && content[idx + 1] == '/'
          while idx < content.size && content[idx] != '\n'
            idx += 1
          end
          next
        end

        # Skip multi-line comments
        if char == '/' && idx + 1 < content.size && content[idx + 1] == '*'
          idx += 2
          while idx + 1 < content.size && !(content[idx] == '*' && content[idx + 1] == '/')
            idx += 1
          end
          idx += 2 if idx + 1 < content.size
          next
        end

        # Skip string literals
        if char == '"' || char == '\''
          quote = char
          idx += 1
          while idx < content.size && content[idx] != quote
            if content[idx] == '\\' && idx + 1 < content.size
              idx += 2
            else
              idx += 1
            end
          end
          idx += 1
          next
        end

        # Skip template literals
        if char == '`'
          idx += 1
          while idx < content.size && content[idx] != '`'
            if content[idx] == '\\' && idx + 1 < content.size
              idx += 2
            else
              idx += 1
            end
          end
          idx += 1
          next
        end

        # Skip regex literals (heuristic: / preceded by operator/punctuation or keyword)
        if char == '/' && idx > 0
          prev_idx = idx - 1
          while prev_idx > 0 && content[prev_idx].whitespace?
            prev_idx -= 1
          end
          prev_char = content[prev_idx]

          # Check if preceded by punctuation that expects expression
          is_regex = prev_char.in?('(', '[', '{', ',', ':', ';', '=', '!', '&', '|', '?', '+', '-', '*', '%', '<', '>', '~', '^')

          # Also check if preceded by keyword that expects expression
          unless is_regex
            # Extract preceding word
            word_end = prev_idx + 1
            word_start = prev_idx
            while word_start > 0 && (content[word_start - 1].alphanumeric? || content[word_start - 1] == '_')
              word_start -= 1
            end
            if word_start < word_end
              prev_word = content[word_start...word_end]
              is_regex = prev_word.in?("return", "case", "throw", "in", "of", "typeof", "instanceof", "void", "delete", "new")
            end
          end

          if is_regex
            idx += 1
            in_char_class = false
            while idx < content.size
              break if content[idx] == '/' && !in_char_class
              if content[idx] == '\\' && idx + 1 < content.size
                idx += 2
              elsif content[idx] == '[' && !in_char_class
                in_char_class = true
                idx += 1
              elsif content[idx] == ']' && in_char_class
                in_char_class = false
                idx += 1
              else
                idx += 1
              end
            end
            idx += 1 if idx < content.size
            # Skip regex flags
            while idx < content.size && content[idx].in?('g', 'i', 'm', 's', 'u', 'y', 'd')
              idx += 1
            end
            next
          end
        end

        case char
        when '('
          paren_count += 1
        when ')'
          paren_count -= 1
        end
        idx += 1

        # Return the position of the matching closing paren
        return idx - 1 if paren_count == 0
      end

      # No matching paren found
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
          # Check if this is already captured (exact match on directory name)
          unless static_paths.any? { |s| s["file_path"] == dir_name || s["file_path"].ends_with?("/#{dir_name}") }
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
