require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/java_route_extractor_ts"
require "wait_group"

module Analyzer::Java
  class Vertx < Analyzer
    # Regex patterns for Vert.x route detection
    REGEX_ROUTER_ROUTE         = /(\w+)\.(get|post|put|delete|patch|head|options|connect|trace)\s*\(([^)]*)\)/i
    REGEX_ROUTE_METHOD         = /(\w+)\.route\s*\(([^)]*)\)\s*\.\s*(get|post|put|delete|patch|head|options|connect|trace)\s*\(/i
    REGEX_ROUTE_HTTP_METHOD    = /(\w+)\.route\s*\(([^)]*)\)/i
    REGEX_ROUTER_ROUTE_HANDLER = /router\.(get|post|put|delete|patch|head|options|connect|trace)\s*\(\s*["\']([^"\']*)["\']\s*\)\s*\.handler\s*\(\s*this::([\w$]+)\s*\)/i
    REGEX_ROUTE_METHOD_HANDLER = /\.route\s*\(\s*["\']([^"\']*)["\']\s*\)\s*\.\s*(get|post|put|delete|patch|head|options|connect|trace)\s*\(\s*this::([\w$]+)\s*\)/i
    REGEX_ROUTE_ANY_HANDLER    = /(\w+)\.route\s*\(([^)]*)\)\s*\.handler\s*\(\s*this::([\w$]+)\s*\)/i
    REGEX_ROUTE_SUB_ROUTER     = /(\w+)\.route\s*\(([^)]*)\)\s*\.subRouter\s*\(/i
    REGEX_MOUNTSUBPATH         = /(\w+)\.mountSubRouter\s*\(([^)]*)\)/i
    REGEX_STATIC_HANDLER_ROUTE = /(\w+)\.route\s*\(([^)]*)\)\s*\.handler\s*\([^;]*StaticHandler\.create\s*\(/im
    HTTP_METHODS               = %w[GET POST PUT DELETE PATCH HEAD OPTIONS CONNECT TRACE]

    private struct RouteCandidate
      getter router_name : String
      getter method : String
      getter endpoint : String

      def initialize(@router_name, @method, @endpoint)
      end
    end

    private struct MountCandidate
      getter parent_router : String
      getter endpoint : String
      getter child_router : String

      def initialize(@parent_router, @endpoint, @child_router)
      end
    end

    def analyze
      # Source Analysis
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            all_files.each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if JavaEngine.test_path?(path)

                  if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
                    details = Details.new(PathInfo.new(path))
                    content = read_file_content(path)

                    # Skip if no Vert.x related content
                    next unless content.includes?("Router") || content.includes?("vertx")

                    callees_by_route = include_callee ? extract_method_reference_callees(content, path) : {} of String => Array(Callee)
                    constants = path.ends_with?(".java") ? Noir::TreeSitterJavaRouteExtractor.extract_string_constants(content) : Hash(String, String).new
                    route_candidates = extract_route_candidates(content, constants)
                    mounts = extract_mounts(content, constants)
                    mounted_routers = Set(String).new
                    mounts.each { |mount| mounted_routers << mount.child_router }

                    route_candidates.each do |route|
                      next if mounted_routers.includes?(route.router_name)

                      found = build_endpoint(route.endpoint, route.method, details)
                      attach_callees(found, callees_by_route, route.method, route.endpoint)
                      @result << found
                    end

                    routes_by_router = route_candidates.group_by(&.router_name)
                    mounts.each do |mount|
                      child_routes = routes_by_router[mount.child_router]?
                      next unless child_routes

                      child_routes.each do |child|
                        endpoint = join_paths(mount.endpoint, child.endpoint)
                        found = build_endpoint(endpoint, child.method, details)
                        attach_callees(found, callees_by_route, child.method, child.endpoint)
                        @result << found
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      Fiber.yield

      @result
    end

    private def extract_route_candidates(content : String, constants : Hash(String, String)) : Array(RouteCandidate)
      candidates = [] of RouteCandidate

      # Find direct router method calls like router.get("/path", handler)
      content.scan(REGEX_ROUTER_ROUTE) do |match|
        next if match.size < 4
        router_name = match[1]
        method = match[2].upcase
        endpoint = resolve_route_path_arg(first_top_level_arg(match[3]), constants)

        next if !method.in?(HTTP_METHODS)
        next if endpoint.nil? || endpoint.empty?

        candidates << RouteCandidate.new(router_name, method, endpoint)
      end

      # Find route().method() pattern calls
      content.scan(REGEX_ROUTE_METHOD) do |match|
        next if match.size < 4
        router_name = match[1]
        endpoint = resolve_route_path_arg(first_top_level_arg(match[2]), constants)
        method = match[3].upcase

        next if !method.in?(HTTP_METHODS)
        next if endpoint.nil? || endpoint.empty?

        candidates << RouteCandidate.new(router_name, method, endpoint)
      end

      # Find route(HttpMethod.METHOD, "/path") pattern calls
      content.scan(REGEX_ROUTE_HTTP_METHOD) do |match|
        next if match.size < 3
        router_name = match[1]
        args = split_top_level_args(match[2])
        next unless args.size >= 2

        method = resolve_http_method_arg(args[0])
        endpoint = resolve_route_path_arg(args[1], constants)

        next if method.nil? || !method.in?(HTTP_METHODS)
        next if endpoint.nil? || endpoint.empty?

        candidates << RouteCandidate.new(router_name, method, endpoint)
      end

      # A Vert.x Route without `.method(...)` or `route(HttpMethod, ...)`
      # matches all HTTP methods. Only capture explicit method-reference
      # handlers here to avoid promoting common middleware routes such as
      # BodyHandler into standalone endpoints.
      content.scan(REGEX_ROUTE_ANY_HANDLER) do |match|
        next if match.size < 3
        router_name = match[1]
        args = split_top_level_args(match[2])
        next unless args.size == 1

        endpoint = resolve_route_path_arg(args[0], constants)
        next if endpoint.nil? || endpoint.empty?

        candidates << RouteCandidate.new(router_name, "ANY", endpoint)
      end

      # `router.route("/prefix/*").subRouter(child)` exposes the child
      # router under that path without constraining the HTTP method.
      # Treat it like the explicit `mountSubRouter` form; unlike generic
      # middleware handlers, this is a concrete mounted route surface.
      content.scan(REGEX_ROUTE_SUB_ROUTER) do |match|
        next if match.size < 3
        router_name = match[1]
        args = split_top_level_args(match[2])
        next unless args.size == 1

        endpoint = resolve_route_path_arg(args[0], constants)
        next if endpoint.nil? || endpoint.empty?

        candidates << RouteCandidate.new(router_name, "ANY", endpoint)
      end

      # Find fluent Route API chains like
      # `router.route().method(HttpMethod.GET).path("/path")`.
      extract_fluent_route_chains(content).each do |entry|
        router_name, chain = entry
        endpoints = fluent_route_paths(chain, constants)
        methods = fluent_route_methods(chain)
        next if endpoints.empty? || methods.empty?

        methods.each do |method|
          endpoints.each do |endpoint|
            candidates << RouteCandidate.new(router_name, method, endpoint)
          end
        end
      end

      # Vert.x static file serving is commonly declared as
      # `router.route("/static/*").handler(StaticHandler.create())`.
      # The route itself has no explicit HTTP method, but this exposes
      # static resources over GET in practice and should be part of the
      # attack surface.
      content.scan(REGEX_STATIC_HANDLER_ROUTE) do |match|
        next if match.size < 3
        router_name = match[1]
        endpoint = resolve_route_path_arg(first_top_level_arg(match[2]), constants)
        next if endpoint.nil? || endpoint.empty?

        candidates << RouteCandidate.new(router_name, "GET", endpoint)
      end

      # A Vert.x Web route path is always anchored at the router root, so
      # the path string passed to `router.get(...)`, `route(...)`,
      # `mountSubRouter(...)`, etc. must start with `/`. Generic
      # `<ident>.get/put/...` calls on collections (`map.put("ez", ...)`,
      # `cache.get("key")`, `headers.get("X")`) share the verb-method
      # spelling but never carry a slash-prefixed first argument, so the
      # leading-slash gate filters them out without a type-tracking pass.
      candidates.select { |candidate| vertx_route_path?(candidate.endpoint) }.uniq!
    end

    # Vert.x Web requires path-string routes to begin with `/` (regex
    # routes go through `routeWithRegex`, which this analyzer doesn't
    # model). Anything else is a collection/`Map` method that merely
    # shares the `get`/`put`/`delete`/... spelling.
    private def vertx_route_path?(endpoint : String) : Bool
      endpoint.starts_with?('/')
    end

    private def extract_mounts(content : String, constants : Hash(String, String)) : Array(MountCandidate)
      mounts = [] of MountCandidate

      content.scan(REGEX_MOUNTSUBPATH) do |match|
        next if match.size < 3
        parent_router = match[1]
        args = split_top_level_args(match[2])
        next unless args.size >= 2

        endpoint = resolve_route_path_arg(args[0], constants)
        child_router = args[1].strip[/\A\w+\z/]?

        next if endpoint.nil? || endpoint.empty? || child_router.nil? || child_router.empty?
        next unless vertx_route_path?(endpoint)

        mounts << MountCandidate.new(parent_router, endpoint, child_router)
      end

      mounts.uniq
    end

    private def first_top_level_arg(args : String) : String
      split_top_level_args(args).first? || ""
    end

    private def split_top_level_args(args : String) : Array(String)
      split_top_level(args, ',')
    end

    private def split_top_level(expr : String, separator : Char) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      quote = '\0'
      escape = false

      expr.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when separator
          next unless depth == 0

          parts << expr[start...index].strip
          start = index + 1
        end
      end

      tail = expr[start..]?.to_s.strip
      parts << tail unless tail.empty?
      parts
    end

    private def resolve_route_path_arg(raw_arg : String, constants : Hash(String, String), depth = 0) : String?
      return if depth > 16

      arg = raw_arg.strip
      return if arg.empty?

      if arg.starts_with?("(") && arg.ends_with?(")")
        return resolve_route_path_arg(arg[1...-1], constants, depth + 1)
      end

      if quoted_string?(arg)
        return arg[1...-1]
      end

      if arg.includes?("+")
        parts = split_top_level(arg, '+')
        return if parts.empty?

        values = parts.map { |part| resolve_route_path_arg(part, constants, depth + 1) }
        return if values.any?(Nil)
        return values.compact.join
      end

      resolve_constant_reference(arg, constants)
    end

    private def resolve_http_method_arg(raw_arg : String) : String?
      arg = raw_arg.strip
      if match = arg.match(/(?:HttpMethod\.)?([A-Z]+)/)
        return match[1].upcase
      end

      nil
    end

    private def extract_fluent_route_chains(content : String) : Array(Tuple(String, String))
      chains = [] of Tuple(String, String)
      content.scan(/(\w+)\.route\s*\(\s*\)/) do |match|
        start = match.end || 0
        statement_end = content.index(';', start) || content.size
        chains << {match[1], content[start...statement_end]}
      end
      chains
    end

    private def fluent_route_paths(chain : String, constants : Hash(String, String)) : Array(String)
      paths = [] of String
      chain.scan(/\.\s*path\s*\(([^)]*)\)/m) do |match|
        if path = resolve_route_path_arg(first_top_level_arg(match[1]), constants)
          paths << path unless path.empty?
        end
      end
      paths.uniq
    end

    private def fluent_route_methods(chain : String) : Array(String)
      methods = [] of String
      chain.scan(/\.\s*method\s*\(([^)]*)\)/m) do |match|
        if method = resolve_http_method_arg(match[1])
          methods << method if method.in?(HTTP_METHODS)
        end
      end
      methods.uniq
    end

    private def resolve_constant_reference(name : String, constants : Hash(String, String)) : String?
      if resolved = constants[name]?
        return resolved
      end

      suffix = ".#{name}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def quoted_string?(value : String) : Bool
      value.size >= 2 &&
        ((value.starts_with?('"') && value.ends_with?('"')) ||
          (value.starts_with?("'") && value.ends_with?("'")))
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    private def build_endpoint(path : String, method : String, details : Details) : Endpoint
      endpoint = Endpoint.new(path, method, details)
      extract_path_parameters(path, endpoint)
      endpoint
    end

    private def extract_path_parameters(path : String, endpoint : Endpoint)
      path.scan(/:(\w+)/) do |match|
        next unless match.size > 1
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end

      path.scan(/\{(\w+)\}/) do |match|
        next unless match.size > 1
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end
    end

    private def extract_method_reference_callees(content : String, path : String) : Hash(String, Array(Callee))
      handlers_by_route = {} of String => String

      content.scan(REGEX_ROUTER_ROUTE_HANDLER) do |match|
        next if match.size < 4
        method = match[1].upcase
        endpoint = match[2]
        handler_name = match[3]
        next if endpoint.empty? || handler_name.empty?

        handlers_by_route[route_key(method, endpoint)] = handler_name
      end

      content.scan(REGEX_ROUTE_METHOD_HANDLER) do |match|
        next if match.size < 4
        endpoint = match[1]
        method = match[2].upcase
        handler_name = match[3]
        next if endpoint.empty? || handler_name.empty?

        handlers_by_route[route_key(method, endpoint)] = handler_name
      end

      return {} of String => Array(Callee) if handlers_by_route.empty?

      wanted_handlers = handlers_by_route.values.uniq!
      callees_by_handler = {} of String => Array(Callee)

      Noir::TreeSitter.parse_java(content) do |root|
        walk_method_declarations(root) do |method|
          name_node = Noir::TreeSitter.field(method, "name")
          next unless name_node

          method_name = Noir::TreeSitter.node_text(name_node, content)
          next unless wanted_handlers.includes?(method_name)
          next if callees_by_handler.has_key?(method_name)

          body = Noir::TreeSitter.field(method, "body")
          next unless body

          callees_by_handler[method_name] = Noir::JavaCalleeExtractor.callees_in_body(body, content, path).map do |(name, callee_path, callee_line)|
            Callee.new(name, path: callee_path, line: callee_line)
          end
        end
      end

      callees_by_route = {} of String => Array(Callee)
      handlers_by_route.each do |key, handler_name|
        if callees = callees_by_handler[handler_name]?
          callees_by_route[key] = callees
        end
      end
      callees_by_route
    end

    private def attach_callees(endpoint : Endpoint, callees_by_route : Hash(String, Array(Callee)), method : String, route : String)
      callees = callees_by_route[route_key(method, route)]?
      return unless callees

      callees.each do |callee|
        endpoint.push_callee(callee)
      end
    end

    private def route_key(method : String, route : String) : String
      "#{method.upcase}::#{route}"
    end

    private def walk_method_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "method_declaration"
        block.call(node)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_method_declarations(child, &block)
      end
    end
  end
end
