require "../../engines/swift_engine"
require "../../../miniparsers/swift_callee_extractor"

module Analyzer::Swift
  class Kitura < SwiftEngine
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    # Patterns for route definitions in Kitura:
    # router.get("path") { ... }
    # router.post("path", handler: handler)
    # router.all("/path") { ... }
    ROUTE_PATTERN              = /(\w+)\.(get|post|put|delete|patch|all)\(([^)]+)\)/
    ROUTE_BODY_LOOKAHEAD_LIMIT = LOOKAHEAD_LIMIT
    FUNCTION_SIGNATURE_PATTERN = /\bfunc\s+([A-Za-z_]\w*)\s*\(/

    # `let router = Router()` / `func boot(router: Router)` — the receivers a
    # Kitura route is registered on. Tracking them makes detection
    # receiver-aware, so look-alike `.get`/`.delete`/... calls on models or
    # services (`Grade.delete(id:)`, `cache.get(...)`) stop becoming phantom
    # endpoints.
    ROUTER_ASSIGN_PATTERN = /\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*Router\s*[(<]/
    ROUTER_PARAM_PATTERN  = /([A-Za-z_]\w*)\s*:\s*Router\b/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      handler_bodies = named_handler_bodies(lines)
      router_receivers = collect_router_receivers(lines)

      lines.each_with_index do |line, index|
        next unless route_definition_line?(line)
        match = line.match(ROUTE_PATTERN)
        next unless match
        next unless router_receivers.includes?(match[1])

        begin
          # Note: 'all' matches all HTTP methods, defaulting to GET for representation
          method_str = match[2]
          method = method_str == "all" ? "GET" : method_str.upcase
          route_args = match[3]
          route_path = parse_route_path(route_args)

          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(route_path, method, details)

          extract_path_params(route_path, endpoint)
          extract_function_params(lines, index + 1, endpoint)
          extract_named_handler_params(lines[index], handler_bodies, endpoint)
          attach_route_callees(lines, index, path, endpoint, handler_bodies) if include_callee

          endpoints << endpoint
        rescue e
          logger.debug "Error processing endpoint: #{e.message}"
        end
      end

      endpoints
    end

    # Parse route path from route arguments
    # Examples:
    # "/hello" -> /hello
    # "/users/:id" -> /users/:id
    # "/api/users/:userID" -> /api/users/:userID
    def parse_route_path(route_args : String) : String
      # Match the first quoted string (the path)
      if match = route_args.match(/["']([^"']+)["']/)
        path = match[1]
        path = "/" + path unless path.starts_with?("/")
        return path
      end

      "/"
    end

    # Extract path parameters from the route pattern (e.g., :id, :userID)
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract parameters from function body
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      in_function = false
      brace_count = 0
      seen_opening_brace = false

      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |i|
        line = lines[i]

        if line.match(/\bin\b/)
          in_function = true
        end

        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        extract_params_from_line(line, endpoint, existing_path_params)

        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        if i > start_index && route_definition?(line)
          break
        end
      end
    end

    # Check if a line contains a route definition
    private def route_definition?(line : String) : Bool
      (line.includes?(".get(") || line.includes?(".post(") ||
        line.includes?(".put(") || line.includes?(".delete(") ||
        line.includes?(".patch(") || line.includes?(".all("))
    end

    # Check if a line is a route definition but not a parameter access
    private def route_definition_line?(line : String) : Bool
      route_definition?(line) &&
        !line.includes?("request.parameters") &&
        !line.includes?("request.queryParameters")
    end

    # The set of router-like receiver names: every `Router()` binding, every
    # `Router`-typed parameter, plus the conventional `router` whenever a
    # `.router` property (`app.router`, `self.router`) is accessed — that
    # access is exactly the receiver `ROUTE_PATTERN` captures for
    # `app.router.get(...)`.
    private def collect_router_receivers(lines : Array(String)) : Set(String)
      receivers = Set(String).new
      lines.each do |line|
        if match = line.match(ROUTER_ASSIGN_PATTERN)
          receivers << match[1]
        end
        line.scan(ROUTER_PARAM_PATTERN) { |m| receivers << m[1] }
        receivers << "router" if line.matches?(/\.router\b/)
      end
      receivers
    end

    private def attach_route_callees(lines : Array(String),
                                     route_index : Int32,
                                     path : String,
                                     endpoint : Endpoint,
                                     handler_bodies : Hash(String, Tuple(String, Int32)))
      body, start_line = route_body(lines, route_index)

      if body.empty?
        body, start_line = named_handler_body(lines, route_index, handler_bodies)
      end

      return if body.empty?

      callees = Noir::SwiftCalleeExtractor.callees_for_body(body, path, start_line)
      Noir::SwiftCalleeExtractor.attach_to(endpoint, callees)
    end

    private def route_body(lines : Array(String), route_index : Int32) : Tuple(String, Int32)
      opening_index = route_index
      opening_brace = structural_opening_brace(lines[opening_index])
      unless opening_brace
        ((route_index + 1)...[route_index + ROUTE_BODY_LOOKAHEAD_LIMIT, lines.size].min).each do |index|
          break if route_definition_line?(lines[index])

          if brace_index = structural_opening_brace(lines[index])
            opening_index = index
            opening_brace = brace_index
            break
          end
        end
      end
      return {"", route_index + 2} unless opening_brace

      body_after_opening_brace(lines, opening_index, opening_brace)
    end

    private def named_handler_body(lines : Array(String),
                                   route_index : Int32,
                                   handler_bodies : Hash(String, Tuple(String, Int32))) : Tuple(String, Int32)
      handler_name = route_handler_name(lines[route_index])
      return {"", route_index + 2} unless handler_name

      handler_bodies[handler_name]? || {"", route_index + 2}
    end

    private def named_handler_bodies(lines : Array(String)) : Hash(String, Tuple(String, Int32))
      bodies = {} of String => Tuple(String, Int32)
      block_comment_depth = 0
      in_multiline_string = false

      lines.each_with_index do |line, index|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        match = stripped.match(FUNCTION_SIGNATURE_PATTERN)
        next unless match

        handler_name = match[1]
        next if bodies.has_key?(handler_name)

        opening = stripped.index('{')
        if opening
          bodies[handler_name] = body_after_opening_brace(lines, index, opening)
          next
        end

        if location = next_opening_brace(lines, index + 1, block_comment_depth, in_multiline_string)
          opening_index, opening_brace = location
          bodies[handler_name] = body_after_opening_brace(lines, opening_index, opening_brace)
        end
      end

      bodies
    end

    private def next_opening_brace(lines : Array(String),
                                   start_index : Int32,
                                   block_comment_depth : Int32,
                                   in_multiline_string : Bool) : Tuple(Int32, Int32)?
      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |index|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          lines[index],
          block_comment_depth,
          in_multiline_string
        )
        if opening = stripped.index('{')
          return {index, opening}
        end

        break if stripped.match(FUNCTION_SIGNATURE_PATTERN)
      end

      nil
    end

    private def route_handler_name(route_line : String) : String?
      stripped, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(route_line, 0, false)
      if match = stripped.match(/handler:\s*([A-Za-z_]\w*)/)
        return match[1]
      end

      nil
    end

    private def extract_named_handler_params(route_line : String,
                                             handler_bodies : Hash(String, Tuple(String, Int32)),
                                             endpoint : Endpoint)
      handler_name = route_handler_name(route_line)
      return unless handler_name

      body = handler_bodies[handler_name]?
      return unless body

      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      body[0].each_line do |line|
        extract_params_from_line(line, endpoint, existing_path_params)
      end
    end

    private def extract_params_from_line(line : String, endpoint : Endpoint, existing_path_params : Set(String))
      # Extract query parameters from request.queryParameters
      if line.includes?("request.queryParameters[")
        match = line.match(/request\.queryParameters\[["']([^"']+)["']\]/)
        if match
          query_name = match[1]
          endpoint.push_param(Param.new(query_name, "", "query"))
        end
      end

      # Extract body parameters from request.body or try? request.read
      if line.includes?("request.body") || line.includes?("request.read")
        endpoint.push_param(Param.new("body", "", "json"))
      end

      # Extract headers from request.headers
      if line.includes?("request.headers[")
        match = line.match(/request\.headers\[["']([^"']+)["']\]/)
        if match
          header_name = match[1]
          endpoint.push_param(Param.new(header_name, "", "header"))
        end
      end

      # Extract cookies from request.cookies
      if line.includes?("request.cookies[")
        match = line.match(/request\.cookies\[["']([^"']+)["']\]/)
        if match
          cookie_name = match[1]
          endpoint.push_param(Param.new(cookie_name, "", "cookie"))
        end
      end

      # Extract path parameters from request.parameters
      if line.includes?("request.parameters[")
        match = line.match(/request\.parameters\[["']([^"']+)["']\]/)
        if match
          param_name = match[1]
          if !existing_path_params.includes?(param_name)
            endpoint.push_param(Param.new(param_name, "", "path"))
            existing_path_params.add(param_name)
          end
        end
      end
    end

    private def body_after_opening_brace(lines : Array(String), opening_index : Int32, opening_brace : Int32) : Tuple(String, Int32)
      opening_line = lines[opening_index]
      first_fragment = opening_line[(opening_brace + 1)..]? || ""
      clean_fragment, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first_fragment, 0, false)
      body_lines = [] of String
      brace_count = 1 + clean_fragment.count('{') - clean_fragment.count('}')

      if brace_count <= 0
        closing_brace = clean_fragment.rindex('}')
        first_fragment = first_fragment[0...closing_brace] if closing_brace
        return {first_fragment, opening_index + 1}
      end

      body_lines << first_fragment
      index = opening_index + 1

      while index < lines.size && brace_count > 0
        line = lines[index]
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        opens = stripped.count('{')
        closes = stripped.count('}')
        next_brace_count = brace_count + opens - closes

        if next_brace_count <= 0
          if line.strip != "}"
            closing_brace = stripped.rindex('}')
            body_lines << (closing_brace ? line[0...closing_brace] : line)
          end
          break
        end

        body_lines << line
        brace_count = next_brace_count

        index += 1
      end

      {body_lines.join("\n"), opening_index + 1}
    end

    private def structural_opening_brace(line : String) : Int32?
      stripped, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, 0, false)
      stripped.index('{')
    end
  end
end
