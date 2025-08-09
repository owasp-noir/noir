require "../models/endpoint"
require "../minilexers/js_lexer"

module Noir
  # JSRoutePattern represents a JavaScript framework route pattern
  class JSRoutePattern
    getter method : String
    property path : String
    getter params : Array(Param)

    def initialize(@method : String, @path : String)
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

    def parse_routes : Array(JSRoutePattern)
      routes = [] of JSRoutePattern
      @framework = detect_framework

      # Add a maximum iteration count to prevent infinite loops
      max_iterations = 10000
      iterations = 0

      # Track route prefixes for handling nested routers
      prefix_stack = [] of String
      current_prefix = ""

      # First pass: scan for router.use("/prefix", ...) patterns to collect prefixes
      idx = 0
      while idx < @tokens.size - 3
        if (@tokens[idx].type == :identifier || @tokens[idx].value.ends_with?("Router")) &&
           idx + 2 < @tokens.size &&
           @tokens[idx + 1].type == :dot &&
           (@tokens[idx + 2].value == "use" || @tokens[idx + 2].value == "register") &&
           idx + 3 < @tokens.size &&
           @tokens[idx + 3].type == :lparen &&
           idx + 4 < @tokens.size &&
           @tokens[idx + 4].type == :string
          # Found a potential prefix in router.use("/prefix", ...)
          prefix = @tokens[idx + 4].value
          prefix_stack << prefix unless prefix.empty?
        end
        idx += 1
      end

      # Second pass: process routes with collected prefixes
      while !is_at_end && iterations < max_iterations
        start_position = @position

        # Try to parse route with current or no prefix
        route = parse_route_pattern
        if route
          # Apply the current prefix if it exists
          if !current_prefix.empty? && !route.path.starts_with?("/")
            route.path = "#{current_prefix}/#{route.path}"
          elsif !current_prefix.empty?
            route.path = "#{current_prefix}#{route.path}"
          end

          routes << route
        end

        # Try various route patterns for different frameworks
        route = parse_express_route_method
        if route
          apply_prefix(route, current_prefix)
          routes << route
        end

        route = parse_fastify_register_route
        if route
          apply_prefix(route, current_prefix)
          routes << route
        end

        route = parse_restify_apply_routes
        if route
          apply_prefix(route, current_prefix)
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
        puts "Warning: Maximum iterations reached in JS parser, parsing may be incomplete"
      end

      # Ensure all routes have leading slash for consistency
      routes.each do |route_item|
        route_item.path = "/#{route_item.path}" unless route_item.path.starts_with?("/")
      end

      routes
    end

    private def apply_prefix(route : JSRoutePattern, prefix : String)
      return if prefix.empty?

      if !route.path.starts_with?("/")
        route.path = "#{prefix}/#{route.path}"
      else
        route.path = "#{prefix}#{route.path}"
      end
    end

    private def current_token
      return JSToken.new(:eof, "", @position) if is_at_end
      @tokens[@position]
    end

    private def advance
      @position += 1 if !is_at_end
      @tokens[@position - 1]
    end

    private def is_at_end
      @position >= @tokens.size
    end

    private def peek
      return JSToken.new(:eof, "", @position) if is_at_end
      @tokens[@position]
    end

    private def check(type : Symbol)
      return false if is_at_end
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

      # Look for app.METHOD or router.METHOD patterns
      while idx < @tokens.size - 2
        if (@tokens[idx].value == "app" ||
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
            # Check for template literal or dynamic path construction
            elsif @tokens[path_idx + 1].type == :template_literal ||
                  @tokens[path_idx + 1].type == :identifier
              resolved_path = resolve_dynamic_path(path_idx + 1)
              if resolved_path
                path = resolved_path
                # Skip past the resolved tokens
                @position = path_idx + 4  # Adjust based on pattern complexity
              end
            end

            if path
              # Extract parameters from path
              route = JSRoutePattern.new(method, path)
              extract_path_params(path).each do |param|
                route.push_param(param)
              end
              return route
            end
          end
        end
        idx += 1
      end

      nil
    end

    private def parse_fastify_route : JSRoutePattern?
      # Similar to Express but with fastify variable name
      idx = @position

      # Look for fastify.METHOD patterns
      while idx < @tokens.size - 2
        if (@tokens[idx].value == "fastify" ||
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
            route = JSRoutePattern.new(method, path)
            extract_path_params(path).each do |param|
              route.push_param(param)
            end

            return route
          end
        end
        idx += 1
      end

      nil
    end

    private def parse_restify_route : JSRoutePattern?
      # Similar to Express but handle restify specific patterns like .del()
      idx = @position

      # Look for server.METHOD patterns
      while idx < @tokens.size - 2
        if (@tokens[idx].value == "server" ||
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
              route = JSRoutePattern.new(method, path)
              extract_path_params(path).each do |param|
                route.push_param(param)
              end
              return route
            end
          end
        end
        idx += 1
      end

      nil
    end

    private def parse_generic_route : JSRoutePattern?
      # For unknown frameworks, just look for HTTP method patterns
      idx = @position

      # Look for .METHOD patterns
      while idx < @tokens.size - 2
        if idx > 0 &&
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
                @position = path_idx + 4  # Adjust based on pattern complexity
              end
            end

            if path
              # Extract parameters from path
              route = JSRoutePattern.new(method, path)
              extract_path_params(path).each do |param|
                route.push_param(param)
              end
              return route
            end
          end
        end
        idx += 1
      end

      nil
    end

    private def parse_express_route_method : JSRoutePattern?
      # Parse app.route('/path').get(...).post(...) patterns
      idx = @position

      while idx < @tokens.size - 5
        if (@tokens[idx].value == "app" ||
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

          # Look for method chaining after .route('/path')
          method_idx = idx + 6 # Skip past closing paren
          while method_idx < @tokens.size - 1
            if @tokens[method_idx].type == :dot &&
               method_idx + 1 < @tokens.size &&
               @tokens[method_idx + 1].type == :http_method
              method = @tokens[method_idx + 1].value.upcase

              # Create a route for this HTTP method
              route = JSRoutePattern.new(method, path)
              extract_path_params(path).each do |param|
                route.push_param(param)
              end

              @position = method_idx + 2 # Move past this method
              return route
            elsif @tokens[method_idx].type != :dot
              # End of method chain
              break
            end
            method_idx += 1
          end
        end
        idx += 1
      end

      nil
    end

    private def parse_fastify_register_route : JSRoutePattern?
      # Parse fastify.register(routes, { prefix: '/api/v1' }) patterns
      idx = @position

      while idx < @tokens.size - 3
        if (@tokens[idx].value == "fastify" || @tokens[idx].value == "app" || @tokens[idx].value == "server") &&
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

                # Create route with the prefix
                route = JSRoutePattern.new(method, "#{prefix}#{path}")
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
        idx += 1
      end

      nil
    end

    private def parse_restify_apply_routes : JSRoutePattern?
      # Parse router.applyRoutes(server, '/prefix') patterns
      idx = @position

      while idx < @tokens.size - 3
        if (@tokens[idx].value.ends_with?("Router") || @tokens[idx].type == :identifier) &&
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

              # Create route with the prefix
              route = JSRoutePattern.new(method, full_path)
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
        idx += 1
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
      return nil if start_idx >= @tokens.size

      # Handle template literal case: `${variable}/path`
      if @tokens[start_idx].type == :template_literal
        template = @tokens[start_idx].value
        # Basic variable substitution for ${variable} patterns
        @constants.each do |var_name, var_value|
          template = template.gsub("${#{var_name}}", var_value)
        end
        return template
      end

      # Handle string concatenation case: variable + '/path'
      if @tokens[start_idx].type == :identifier &&
         start_idx + 2 < @tokens.size &&
         @tokens[start_idx + 1].type == :plus &&
         @tokens[start_idx + 2].type == :string
        var_name = @tokens[start_idx].value
        if @constants.has_key?(var_name)
          return @constants[var_name] + @tokens[start_idx + 2].value
        end
      end

      # Handle string + variable case: '/path' + variable
      if @tokens[start_idx].type == :string &&
         start_idx + 2 < @tokens.size &&
         @tokens[start_idx + 1].type == :plus &&
         @tokens[start_idx + 2].type == :identifier
        var_name = @tokens[start_idx + 2].value
        if @constants.has_key?(var_name)
          return @tokens[start_idx].value + @constants[var_name]
        end
      end

      nil
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
