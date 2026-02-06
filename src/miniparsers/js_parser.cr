require "../models/endpoint"
require "../minilexers/js_lexer"
require "set"

module Noir
  # JSRoutePattern represents a JavaScript framework route pattern
  class JSRoutePattern
    getter method : String
    property path : String
    getter raw_path : String
    getter start_pos : Int32
    getter params : Array(Param)

    def initialize(@method : String, @path : String, raw_path : String? = nil, @start_pos : Int32 = -1)
      @raw_path = raw_path || @path
      @params = [] of Param
    end

    def push_param(param : Param)
      @params << param
    end
  end

  # JSParser is a simple parser for JavaScript route-related patterns
  class JSParser
    @tokens : Array(JSToken) = [] of JSToken
    @position : Int32 = 0
    @framework : Symbol = :unknown
    @constants : Hash(String, String) = {} of String => String
    @current_route_path : String? = nil
    @current_route_start_idx : Int32? = nil
    @current_route_raw_path : String? = nil
    @current_route_start_pos : Int32? = nil
    @router_prefixes : Hash(String, String) = {} of String => String

    def initialize(source : String)
      lexer = JSLexer.new(source)
      @tokens = lexer.tokenize
      # Extract constants from the source
      extract_constants
    end

    def detect_framework : Symbol
      # Check if any tokens match framework patterns
      @tokens.each do |token|
        case token.value
        when "express"
          return :express
        when "fastify"
          return :fastify
        when "restify"
          return :restify
        end
      end
      :unknown
    end

    @hit_max_iterations : Bool = false

    def hit_max_iterations?
      @hit_max_iterations
    end

    def parse_routes : Array(JSRoutePattern)
      routes = [] of JSRoutePattern
      @framework = detect_framework

      # Add a maximum iteration count to prevent infinite loops
      max_iterations = 10000
      iterations = 0

      # Track router mount paths: router_variable_name => prefix_path
      router_prefixes = Hash(String, String).new
      router_parents = Hash(String, String).new  # For nested routers (child => parent)
      router_variables = Set(String).new  # Track which identifiers are routers

      # First pass: scan for router.use("/prefix", routerVariable) patterns
      idx = 0
      while idx < @tokens.size - 6
        # Pattern: app.use('/prefix', routerVariable) or router.use('/prefix', childRouter)
        if (@tokens[idx].type == :identifier) &&
           (idx + 1 < @tokens.size) && (@tokens[idx + 1].type == :dot) &&
           (idx + 2 < @tokens.size) && (@tokens[idx + 2].value == "use" || @tokens[idx + 2].value == "register") &&
           (idx + 3 < @tokens.size) && (@tokens[idx + 3].type == :lparen) &&
           (idx + 4 < @tokens.size) && (@tokens[idx + 4].type == :string) &&
           (idx + 5 < @tokens.size) && (@tokens[idx + 5].type == :comma) &&
           (idx + 6 < @tokens.size) && (@tokens[idx + 6].type == :identifier)

          parent_router = @tokens[idx].value
          prefix = @tokens[idx + 4].value
          child_router = @tokens[idx + 6].value

          router_prefixes[child_router] = prefix
          router_parents[child_router] = parent_router
          router_variables.add(child_router)
        end
        idx += 1
      end

      # Resolve full paths for nested routers by walking up the parent chain
      router_prefixes.keys.each do |router_name|
        full_prefix = resolve_full_prefix(router_name, router_prefixes, router_parents)
        router_prefixes[router_name] = full_prefix
      end

      @router_prefixes = router_prefixes

      # First, run a fast token scan to quickly capture common patterns
      routes.concat(fast_scan_routes(router_prefixes))

      # Second pass: process routes with other parsing methods
      while !at_end? && iterations < max_iterations
        start_position = @position

        # Try to parse route with current or no prefix
        route = parse_route_pattern
        if route
          routes << route
        end

        # Try various route patterns for different frameworks
        route = parse_express_route_method
        if route
          routes << route
        end

        route = parse_fastify_register_route
        if route
          routes << route
        end

        route = parse_restify_apply_routes
        if route
          routes << route
        end

        # If position didn't change, advance it manually to prevent infinite loops
        if start_position == @position
          @position += 1
        end

        iterations += 1
      end

      # Log a warning if we hit the iteration limit
      if iterations >= max_iterations
        @hit_max_iterations = true
      end

      # Ensure all routes have leading slash for consistency
      routes.each do |route_item|
        route_item.path = "/#{route_item.path}" unless route_item.path.starts_with?("/")
      end

      # Dedupe by method + path
      seen = Set(String).new
      unique = [] of JSRoutePattern
      routes.each do |r|
        key = r.method + "\u0000" + r.path + "\u0000" + r.start_pos.to_s
        next if seen.includes?(key)
        seen.add(key)
        unique << r
      end

      unique
    end

    private def apply_prefix(route : JSRoutePattern, prefix : String)
      return if prefix.empty?

      if !route.path.starts_with?("/")
        route.path = "#{prefix}/#{route.path}"
      else
        route.path = "#{prefix}#{route.path}"
      end
    end

    # Resolve full prefix for a router by walking up the parent chain
    private def resolve_full_prefix(router : String, router_prefixes : Hash(String, String), router_parents : Hash(String, String)) : String
      prefix = router_prefixes[router]? || ""
      current = router
      visited = Set(String).new  # Track visited routers to prevent infinite loops

      # Walk up parent chain
      while parent = router_parents[current]?
        break if visited.includes?(current)  # Prevent infinite loops
        visited.add(current)

        parent_prefix = router_prefixes[parent]? || ""

        # Concatenate paths properly
        if !parent_prefix.empty?
          prefix = join_paths(parent_prefix, prefix)
        end

        current = parent
      end

      prefix
    end

    # Helper to join two path segments properly
    private def join_paths(parent : String, child : String) : String
      return child if parent.empty?
      return parent if child.empty?
      return parent if child == "/"

      if parent.ends_with?("/") && child.starts_with?("/")
        "#{parent[0..-2]}#{child}"
      elsif !parent.ends_with?("/") && !child.starts_with?("/")
        "#{parent}/#{child}"
      else
        "#{parent}#{child}"
      end
    end

    private def format_regex_path(value : String) : String
      parts = value.split("\n", 2)
      pattern = parts[0]
      flags = parts.size > 1 ? parts[1] : ""

      return "/#{pattern}/#{flags}" unless flags.empty?
      "/#{pattern}/"
    end

    # Extract array paths from array syntax: ['/path1', '/path2', /regex/]
    private def extract_array_paths(start_idx : Int32) : Array(String)
      paths = [] of String
      return paths unless start_idx < @tokens.size && @tokens[start_idx].type == :lbracket

      idx = start_idx + 1
      while idx < @tokens.size && @tokens[idx].type != :rbracket
        token = @tokens[idx]

        if token.type == :string
          paths << token.value
        elsif token.type == :regex
          paths << format_regex_path(token.value)
        elsif token.type == :identifier || token.type == :template_literal
          resolved = resolve_dynamic_path(idx)
          paths << resolved if resolved
        end

        idx += 1
        # Skip commas
        idx += 1 if idx < @tokens.size && @tokens[idx].type == :comma
      end

      paths
    end

    private def current_token
      return JSToken.new(:eof, "", @position) if at_end?
      @tokens[@position]
    end

    private def advance
      @position += 1 if !at_end?
      @tokens[@position - 1]
    end

    private def at_end?
      @position >= @tokens.size
    end

    private def peek
      return JSToken.new(:eof, "", @position) if at_end?
      @tokens[@position]
    end

    private def check(type : Symbol)
      return false if at_end?
      peek.type == type
    end

    private def match(types : Array(Symbol))
      types.each do |type|
        if check(type)
          advance
          return true
        end
      end

      false
    end

    private def parse_route_pattern : JSRoutePattern?
      # Parse 'app.get("/path", ...' or 'router.get("/path", ...' patterns
      case @framework
      when :express
        parse_express_route
      when :fastify
        parse_fastify_route
      when :restify
        parse_restify_route
      else
        # Generic parsing for common patterns
        parse_generic_route
      end
    end

    # Fast path: scan tokens for the most common route patterns without full parsing
    private def fast_scan_routes(router_prefixes : Hash(String, String) = Hash(String, String).new) : Array(JSRoutePattern)
      results = [] of JSRoutePattern

      idx = 0
      limit = @tokens.size

      while idx < limit - 4
        # Pattern 1: identifier . http_method ( 'path' | `tpl` | identifier/concat )
        if @tokens[idx].type == :identifier &&
           @tokens[idx + 1].type == :dot &&
           @tokens[idx + 2].type == :http_method &&
           @tokens[idx + 3].type == :lparen
          router_var = @tokens[idx].value
          method = @tokens[idx + 2].value
          # read path at idx+4
          path_token = @tokens[idx + 4]
          paths = [] of String

          if path_token.type == :lbracket
            # Handle array of paths
            paths = extract_array_paths(idx + 4)
          elsif path_token.type == :string || path_token.type == :template_literal || path_token.type == :identifier
            path = resolve_dynamic_path(idx + 4)
            path ||= (path_token.type == :string ? path_token.value : nil)
            paths = [path] if path
          elsif path_token.type == :regex
            path = format_regex_path(path_token.value)
            paths = [path]
          end

          # Create one route for each path
          paths.each do |path|
            raw_path = path
            start_pos = @tokens[idx].position
            # Apply router prefix if this router has one
            if router_prefixes.has_key?(router_var)
              prefix = router_prefixes[router_var]
              path = join_paths(prefix, path)
            end

            m = method.upcase
            m = "DELETE" if m.downcase == "del"
            route = JSRoutePattern.new(m, path, raw_path, start_pos)
            # Only extract path params from non-regex patterns
            unless path.starts_with?("/") && path.includes?("(") && path.includes?(")")
              extract_path_params(path).each { |p| route.push_param(p) }
            end
            results << route
          end

          idx += 1
          next
        end

        # Pattern 2: identifier . route ( 'path' | `tpl` | ident | [ ] ) . http_method ... (chained)
        if @tokens[idx].type == :identifier &&
           @tokens[idx + 1].type == :dot &&
           @tokens[idx + 2].value == "route" &&
           @tokens[idx + 3].type == :lparen
          router_var = @tokens[idx].value
          # resolve path at idx+4
          paths = [] of String
          if idx + 4 < limit
            t = @tokens[idx + 4]
            if t.type == :lbracket
              # Handle array of paths
              paths = extract_array_paths(idx + 4)
            elsif t.type == :string || t.type == :template_literal || t.type == :identifier
              path = resolve_dynamic_path(idx + 4)
              path ||= (t.type == :string ? t.value : nil)
              paths = [path] if path
            elsif t.type == :regex
              paths = [format_regex_path(t.value)]
            end
          end

          paths.each do |base_path|
            path = base_path
            raw_path = base_path
            start_pos = @tokens[idx].position
            # Apply router prefix if this router has one
            if router_prefixes.has_key?(router_var)
              prefix = router_prefixes[router_var]
              path = join_paths(prefix, path)
            end

            # look ahead bounded to avoid O(n^2)
            j = idx + 5
            steps = 0
            max_steps = 1000
            while j < limit - 1 && steps < max_steps
              if @tokens[j].type == :dot && @tokens[j + 1].type == :http_method
                m = @tokens[j + 1].value.upcase
                m = "DELETE" if m.downcase == "del"
                route = JSRoutePattern.new(m, path, raw_path, start_pos)
                # Only extract path params from non-regex patterns
                unless path.starts_with?("/") && path.includes?("(") && path.includes?(")")
                  extract_path_params(path).each { |p| route.push_param(p) }
                end
                results << route
                j += 2
                steps += 2
                next
              elsif @tokens[j].type == :semicolon
                break
              end
              j += 1
              steps += 1
            end
          end

          idx += 1
          next
        end

        idx += 1
      end

      results
    end

    private def extract_path_string(start_token_idx = @position) : String?
      # Look for a string token that might represent a route path
      idx = start_token_idx

      # Find the first string after a dot and HTTP method
      while idx < @tokens.size
        if idx > 1 &&
           @tokens[idx - 2].type == :dot &&
           @tokens[idx - 1].type == :http_method &&
           @tokens[idx].type == :lparen &&
           idx + 1 < @tokens.size &&
           @tokens[idx + 1].type == :string
          return @tokens[idx + 1].value
        end
        idx += 1
      end

      nil
    end

    private def parse_express_route : JSRoutePattern?
      idx = @position

      # Look for app.METHOD or router.METHOD patterns - only at current position
      if idx < @tokens.size - 2 &&
         (@tokens[idx].value == "app" ||
         @tokens[idx].value == "router" ||
         @tokens[idx].value.ends_with?("Router")) &&
         idx + 2 < @tokens.size &&
         @tokens[idx + 1].type == :dot &&
         @tokens[idx + 2].type == :http_method
        method = @tokens[idx + 2].value.upcase

        # Look for the path string in parentheses
        path_idx = idx + 3
        if path_idx < @tokens.size &&
           @tokens[path_idx].type == :lparen &&
           path_idx + 1 < @tokens.size
          path = nil
          # Check for regular string
          if @tokens[path_idx + 1].type == :string
            path = @tokens[path_idx + 1].value
            @position = path_idx + 2
          elsif @tokens[path_idx + 1].type == :regex
            # Handle regex route path
            path = format_regex_path(@tokens[path_idx + 1].value)
            @position = path_idx + 2
            # Check for template literal or dynamic path construction
          elsif @tokens[path_idx + 1].type == :template_literal ||
                @tokens[path_idx + 1].type == :identifier
            resolved_path = resolve_dynamic_path(path_idx + 1)
            if resolved_path
              path = resolved_path
              # Skip past the resolved tokens - find the end of the expression
              skip_idx = path_idx + 1
              while skip_idx < @tokens.size &&
                    (@tokens[skip_idx].type == :identifier ||
                    @tokens[skip_idx].type == :plus ||
                    @tokens[skip_idx].type == :string ||
                    @tokens[skip_idx].type == :template_literal)
                skip_idx += 1
              end
              @position = skip_idx
            end
          end

          if path
            router_var = @tokens[idx].value
            raw_path = path
            start_pos = @tokens[idx].position
            if @router_prefixes.has_key?(router_var)
              prefix = @router_prefixes[router_var]
              path = join_paths(prefix, path)
            end

            # Extract parameters from path
            route = JSRoutePattern.new(method, path, raw_path, start_pos)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end
            return route
          end
        end
      end

      nil
    end

    private def parse_fastify_route : JSRoutePattern?
      # Similar to Express but with fastify variable name
      # Only check at current position
      idx = @position

      # Look for fastify.METHOD patterns
      if idx < @tokens.size - 2 &&
         (@tokens[idx].value == "fastify" ||
         @tokens[idx].value == "app" ||
         @tokens[idx].value == "server") &&
         idx + 2 < @tokens.size &&
         @tokens[idx + 1].type == :dot &&
         @tokens[idx + 2].type == :http_method
        method = @tokens[idx + 2].value.upcase

        # Look for the path string in parentheses
        path_idx = idx + 3
        if path_idx < @tokens.size &&
           @tokens[path_idx].type == :lparen &&
           path_idx + 1 < @tokens.size &&
           @tokens[path_idx + 1].type == :string
          path = @tokens[path_idx + 1].value

          # Advance our position past what we've parsed
          @position = path_idx + 2

          # Extract parameters from path
          start_pos = @tokens[idx].position
          route = JSRoutePattern.new(method, path, nil, start_pos)
          extract_path_params(path).each do |param|
            route.push_param(param)
          end

          return route
        end
      end

      nil
    end

    private def parse_restify_route : JSRoutePattern?
      # Similar to Express but handle restify specific patterns like .del()
      # Only check at current position
      idx = @position

      # Look for server.METHOD patterns
      if idx < @tokens.size - 2 &&
         (@tokens[idx].value == "server" ||
         @tokens[idx].value == "router" ||
         @tokens[idx].value.ends_with?("Router")) &&
         idx + 2 < @tokens.size &&
         @tokens[idx + 1].type == :dot &&
         @tokens[idx + 2].type == :http_method
        method = @tokens[idx + 2].value
        # Handle restify's 'del' method which means DELETE
        method = "DELETE" if method.downcase == "del"
        method = method.upcase

        # Look for the path string in parentheses
        path_idx = idx + 3
        if path_idx < @tokens.size &&
           @tokens[path_idx].type == :lparen &&
           path_idx + 1 < @tokens.size
          path = nil
          # Handle both string and object pattern { path: '/route' }
          if @tokens[path_idx + 1].type == :string
            path = @tokens[path_idx + 1].value
            @position = path_idx + 2
          elsif @tokens[path_idx + 1].type == :lbrace
            # Look for path property in object
            obj_idx = path_idx + 1
            while obj_idx < @tokens.size && @tokens[obj_idx].type != :rbrace
              if @tokens[obj_idx].value == "path" &&
                 obj_idx + 1 < @tokens.size &&
                 @tokens[obj_idx + 1].type == :colon &&
                 obj_idx + 2 < @tokens.size &&
                 @tokens[obj_idx + 2].type == :string
                path = @tokens[obj_idx + 2].value
                @position = obj_idx + 3
                break
              end
              obj_idx += 1
            end
          end

          # If we found a path, create a route object
          if path
            start_pos = @tokens[idx].position
            route = JSRoutePattern.new(method, path, nil, start_pos)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end
            return route
          end
        end
      end

      nil
    end

    private def parse_generic_route : JSRoutePattern?
      # For unknown frameworks, just look for HTTP method patterns
      # Only check at current position
      idx = @position

      # Look for .METHOD patterns
      if idx > 0 &&
         idx < @tokens.size - 2 &&
         @tokens[idx].type == :dot &&
         @tokens[idx + 1].type == :http_method
        method = @tokens[idx + 1].value.upcase

        # Look for the path string in parentheses
        path_idx = idx + 2
        if path_idx < @tokens.size &&
           @tokens[path_idx].type == :lparen &&
           path_idx + 1 < @tokens.size
          path = nil
          # Check for regular string
          if @tokens[path_idx + 1].type == :string
            path = @tokens[path_idx + 1].value
            @position = path_idx + 2
            # Check for template literal or dynamic path construction
          elsif @tokens[path_idx + 1].type == :template_literal ||
                @tokens[path_idx + 1].type == :identifier
            resolved_path = resolve_dynamic_path(path_idx + 1)
            if resolved_path
              path = resolved_path
              # Skip past the resolved tokens - find the end of the expression
              skip_idx = path_idx + 1
              while skip_idx < @tokens.size &&
                    (@tokens[skip_idx].type == :identifier ||
                    @tokens[skip_idx].type == :plus ||
                    @tokens[skip_idx].type == :string ||
                    @tokens[skip_idx].type == :template_literal)
                skip_idx += 1
              end
              @position = skip_idx
            end
          end

          if path
            raw_path = path
            start_pos = @tokens[idx].position
            if @tokens[idx - 1].type == :identifier
              router_var = @tokens[idx - 1].value
              if @router_prefixes.has_key?(router_var)
                prefix = @router_prefixes[router_var]
                path = join_paths(prefix, path)
              end
            end

            # Extract parameters from path
            route = JSRoutePattern.new(method, path, raw_path, start_pos)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end
            return route
          end
        end
      end

      nil
    end

    private def parse_express_route_method : JSRoutePattern?
      # Parse app.route('/path').get(...).post(...) patterns
      idx = @position

      # First, check if we're continuing a chained route
      if @current_route_path.is_a?(String) && @current_route_start_idx
        # We're in the middle of a chain, look for the next method
        # Start from current position and scan forward
        method_idx = @position
        paren_depth = 0

        # First, skip past any function call we might be in the middle of
        while method_idx < @tokens.size
          if @tokens[method_idx].type == :lparen
            paren_depth += 1
          elsif @tokens[method_idx].type == :rparen
            paren_depth -= 1
            if paren_depth == 0
              method_idx += 1
              break
            end
          end
          method_idx += 1
        end

        # Now look for the next chained method
        while method_idx < @tokens.size - 1
          if @tokens[method_idx].type == :dot &&
             method_idx + 1 < @tokens.size &&
             @tokens[method_idx + 1].type == :http_method
            method = @tokens[method_idx + 1].value.upcase

            # Create a route for this HTTP method
            path = @current_route_path.as(String)
            raw_path = @current_route_raw_path || path
            start_pos = @current_route_start_pos || @tokens[@current_route_start_idx.as(Int32)].position
            route = JSRoutePattern.new(method, path, raw_path, start_pos)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end

            @position = method_idx + 2 # Move past the dot and method name
            # Don't reset yet - there might be more methods chained
            return route
          elsif @tokens[method_idx].type == :semicolon ||
                (@tokens[method_idx].value == "route" && method_idx > @position + 5)
            # End of chain
            break
          end

          method_idx += 1
        end

        # No more methods found in chain, reset
        @current_route_path = nil
        @current_route_start_idx = nil
        @current_route_raw_path = nil
        @current_route_start_pos = nil
      end

      # Look for a new route() declaration - only at the current position
      # The main loop will iterate through all positions
      if idx < @tokens.size - 5 &&
         (@tokens[idx].value == "app" ||
         @tokens[idx].value == "router" ||
         @tokens[idx].value.ends_with?("Router")) &&
         idx + 2 < @tokens.size &&
         @tokens[idx + 1].type == :dot &&
         @tokens[idx + 2].value == "route" &&
         idx + 3 < @tokens.size &&
         @tokens[idx + 3].type == :lparen &&
         idx + 4 < @tokens.size &&
         @tokens[idx + 4].type == :string
        path = @tokens[idx + 4].value
        router_var = @tokens[idx].value
        raw_path = path
        start_pos = @tokens[idx].position
        if @router_prefixes.has_key?(router_var)
          prefix = @router_prefixes[router_var]
          path = join_paths(prefix, path)
        end

        # Look for method chaining after .route('/path')
        method_idx = idx + 6 # Skip past string and closing paren
        while method_idx < @tokens.size - 1
          if @tokens[method_idx].type == :dot &&
             method_idx + 1 < @tokens.size &&
             @tokens[method_idx + 1].type == :http_method
            method = @tokens[method_idx + 1].value.upcase

            # Create a route for this HTTP method
            route = JSRoutePattern.new(method, path, raw_path, start_pos)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end

            # Set up for chain continuation
            @current_route_path = path
            @current_route_start_idx = idx
            @current_route_raw_path = raw_path
            @current_route_start_pos = start_pos
            @position = method_idx + 2 # Move past dot and method
            return route
          elsif @tokens[method_idx].type == :semicolon
            # End of statement without finding a method
            break
          end
          method_idx += 1
        end
      end

      nil
    end

    private def parse_fastify_register_route : JSRoutePattern?
      # Parse fastify.register(routes, { prefix: '/api/v1' }) patterns
      # Only check at the current position to avoid skipping other routes
      idx = @position

      if idx < @tokens.size - 3 &&
         (@tokens[idx].value == "fastify" || @tokens[idx].value == "app" || @tokens[idx].value == "server") &&
         idx + 2 < @tokens.size &&
         @tokens[idx + 1].type == :dot &&
         @tokens[idx + 2].value == "register" &&
         idx + 3 < @tokens.size &&
         @tokens[idx + 3].type == :lparen
        # Skip to the options object
        options_idx = idx + 4
        prefix = ""

        # Look for { prefix: '/path' } pattern
        while options_idx < @tokens.size && @tokens[options_idx].type != :rbrace
          if @tokens[options_idx].value == "prefix" &&
             options_idx + 1 < @tokens.size &&
             @tokens[options_idx + 1].type == :colon &&
             options_idx + 2 < @tokens.size &&
             @tokens[options_idx + 2].type == :string
            prefix = @tokens[options_idx + 2].value
            break
          end
          options_idx += 1
        end

        if !prefix.empty?
          # Look ahead for potential routes within the registered module
          ahead_idx = options_idx + 3 # Skip past the closing brace
          while ahead_idx < @tokens.size - 3
            if ahead_idx + 2 < @tokens.size &&
               @tokens[ahead_idx + 1].type == :dot &&
               @tokens[ahead_idx + 2].type == :http_method &&
               ahead_idx + 3 < @tokens.size &&
               @tokens[ahead_idx + 3].type == :lparen &&
               ahead_idx + 4 < @tokens.size &&
               @tokens[ahead_idx + 4].type == :string
              method = @tokens[ahead_idx + 2].value.upcase
              path = @tokens[ahead_idx + 4].value
              start_pos = @tokens[ahead_idx].position

              # Create route with the prefix
              raw_path = path
              route = JSRoutePattern.new(method, "#{prefix}#{path}", raw_path, start_pos)
              extract_path_params(path).each do |param|
                route.push_param(param)
              end

              @position = ahead_idx + 5
              return route
            end
            ahead_idx += 1
          end
        end
      end

      nil
    end

    private def parse_restify_apply_routes : JSRoutePattern?
      # Parse router.applyRoutes(server, '/prefix') patterns
      # Only check at the current position to avoid skipping other routes
      idx = @position

      if idx < @tokens.size - 3 &&
         (@tokens[idx].value.ends_with?("Router") || @tokens[idx].type == :identifier) &&
         idx + 2 < @tokens.size &&
         @tokens[idx + 1].type == :dot &&
         @tokens[idx + 2].value == "applyRoutes" &&
         idx + 3 < @tokens.size &&
         @tokens[idx + 3].type == :lparen
        # Look for prefix in second parameter
        prefix = ""
        if idx + 5 < @tokens.size && @tokens[idx + 5].type == :string
          prefix = @tokens[idx + 5].value
        end

        # Look back for routes defined on this router
        router_name = @tokens[idx].value
        back_idx = idx - 1
        route_count = 0

        while back_idx > 0 && route_count < 20 # Limit backward search
          if back_idx > 2 &&
             @tokens[back_idx - 2].value == router_name &&
             @tokens[back_idx - 1].type == :dot &&
             (@tokens[back_idx].type == :http_method ||
             @tokens[back_idx].value == "del") && # Restify uses 'del' for DELETE
             back_idx + 1 < @tokens.size &&
             @tokens[back_idx + 1].type == :lparen &&
             back_idx + 2 < @tokens.size &&
             @tokens[back_idx + 2].type == :string
            method = @tokens[back_idx].value.upcase
            # Handle restify's 'del' method which means DELETE
            method = "DELETE" if method.downcase == "del"

            path = @tokens[back_idx + 2].value
            full_path = prefix.empty? ? path : "#{prefix}#{path}"
            start_pos = @tokens[back_idx - 2].position

            # Create route with the prefix
            raw_path = path
            route = JSRoutePattern.new(method, full_path, raw_path, start_pos)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end

            @position = back_idx + 3
            return route
          end
          back_idx -= 1
          route_count += 1
        end
      end

      nil
    end

    # Extract constant assignments from the tokens
    private def extract_constants
      idx = 0
      while idx < @tokens.size - 4
        # Look for const/let/var variableName = 'value' patterns
        if (@tokens[idx].value == "const" || @tokens[idx].value == "let" || @tokens[idx].value == "var") &&
           idx + 4 < @tokens.size &&
           @tokens[idx + 1].type == :identifier &&
           @tokens[idx + 2].value == "=" &&
           (@tokens[idx + 3].type == :string || @tokens[idx + 3].type == :template_literal)
          var_name = @tokens[idx + 1].value
          var_value = @tokens[idx + 3].value
          @constants[var_name] = var_value
        end
        idx += 1
      end
    end

    # Resolve dynamic path construction (template literals and concatenation)
    private def resolve_dynamic_path(start_idx : Int32) : String?
      return if start_idx >= @tokens.size

      # Handle pure template literal case: `${variable}/path`
      if @tokens[start_idx].type == :template_literal &&
         (start_idx + 1 >= @tokens.size || @tokens[start_idx + 1].type != :plus)
        template = @tokens[start_idx].value
        # Basic variable substitution for ${variable} patterns
        @constants.each do |var_name, var_value|
          template = template.gsub("${#{var_name}}", var_value)
        end
        return template
      end

      # Handle string concatenation cases (including template literals in concatenation)
      result = ""
      idx = start_idx

      # Parse concatenation chain: var1 + var2 + '/path' + var3
      while idx < @tokens.size
        if @tokens[idx].type == :identifier
          var_name = @tokens[idx].value
          if @constants.has_key?(var_name)
            result += @constants[var_name]
          else
            result += var_name # Keep variable name if not resolved
          end
        elsif @tokens[idx].type == :string
          result += @tokens[idx].value
        elsif @tokens[idx].type == :template_literal
          template = @tokens[idx].value
          # Basic variable substitution for ${variable} patterns
          @constants.each do |const_name, const_value|
            template = template.gsub("${#{const_name}}", const_value)
          end
          result += template
        elsif @tokens[idx].type == :plus
          # Continue to next token
        else
          # End of concatenation chain
          break
        end

        idx += 1

        # Stop if we don't see a plus operator for continuation
        if idx < @tokens.size && @tokens[idx].type != :plus
          break
        elsif idx < @tokens.size && @tokens[idx].type == :plus
          idx += 1 # Skip the plus
        end
      end

      result.empty? ? nil : result
    end

    private def extract_path_params(path : String) : Array(Param)
      params = [] of Param

      # Extract path parameters like :id or {id}
      path.scan(/:(\w+)/) do |match|
        if match.size > 0
          params << Param.new(match[1], "", "path")
        end
      end

      # Also extract {param} style (Express 4 style)
      path.scan(/\{(\w+)\}/) do |match|
        if match.size > 0
          params << Param.new(match[1], "", "path")
        end
      end

      params
    end
  end
end
