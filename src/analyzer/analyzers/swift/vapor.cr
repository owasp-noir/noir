require "../../engines/swift_engine"
require "../../../miniparsers/swift_callee_extractor"

module Analyzer::Swift
  class Vapor < SwiftEngine
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    # Patterns for route definitions in Vapor:
    # app.get("path") { ... }
    # app.post("path", "segment") { ... }
    # routes.get("path", ":param") { ... }
    ROUTE_PATTERN              = /([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.(get|post|put|delete|patch)\s*\((.*)\)/
    ON_ROUTE_PATTERN           = /([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.on\s*\(\s*\.(GET|POST|PUT|DELETE|PATCH)\s*,(.*)\)/
    GROUP_ASSIGN_PATTERN       = /\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\.grouped\s*\((.*)\)/
    GROUP_CLOSURE_PATTERN      = /([A-Za-z_]\w*)\.group(?:ed)?\s*\((.*)\)\s*\{\s*([A-Za-z_]\w*)\s+in/
    FUNCTION_SIGNATURE_PATTERN = /\bfunc\s+([A-Za-z_]\w*)\s*\(/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      handler_bodies = named_handler_bodies(lines)
      prefix_by_receiver = {} of String => String
      group_prefix_stack = [] of Tuple(String, Int32)
      brace_depth = 0

      lines.each_with_index do |line, index|
        stripped_line = code_line(line)
        register_group_assignment(stripped_line, prefix_by_receiver)
        register_group_closure(stripped_line, prefix_by_receiver, group_prefix_stack, brace_depth)

        route = route_parts(stripped_line)
        unless route
          brace_depth = update_group_depth(stripped_line, brace_depth, group_prefix_stack, prefix_by_receiver)
          next
        end

        begin
          receiver, method, route_args = route
          route_path = join_paths(prefix_for_receiver(receiver, prefix_by_receiver), parse_route_path(route_args))

          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(route_path, method, details)

          extract_path_params(route_path, endpoint)
          extract_function_params(lines, index + 1, endpoint)
          extract_named_handler_params(lines[index], handler_bodies, endpoint)
          attach_route_callees(lines, index, path, endpoint, handler_bodies) if include_callee

          endpoints << endpoint
        rescue e
          logger.debug "Error processing endpoint: #{e.message}"
        ensure
          brace_depth = update_group_depth(stripped_line, brace_depth, group_prefix_stack, prefix_by_receiver)
        end
      end

      endpoints
    end

    # Parse route path from route arguments
    # Examples:
    # "hello" -> /hello
    # "users", ":id" -> /users/:id
    # "api", "users", ":userID" -> /api/users/:userID
    def parse_route_path(route_args : String) : String
      # Remove whitespace and split by comma
      segments = route_args.split(',').map(&.strip)

      # Extract quoted strings only (path segments)
      path_segments = [] of String
      segments.each do |seg|
        break if seg.match(/^\w+\s*:/)

        # Match quoted strings
        if match = seg.match(/^["']([^"']+)["']/)
          path_segments << match[1]
        end
      end

      # Build the path
      if path_segments.empty?
        return "/"
      end

      path = "/" + path_segments.join("/")
      path
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

        if line.includes?(" in ")
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
      line.includes?(".get(") || line.includes?(".post(") ||
        line.includes?(".put(") || line.includes?(".delete(") ||
        line.includes?(".patch(") || line.includes?(".on(")
    end

    # Check if a line is a route definition but not a parameter access
    private def route_definition_line?(line : String) : Bool
      route_definition?(line) &&
        !line.includes?("req.parameters") &&
        !line.includes?("req.query")
    end

    private def attach_route_callees(lines : Array(String),
                                     route_index : Int32,
                                     path : String,
                                     endpoint : Endpoint,
                                     handler_bodies : Hash(String, Tuple(String, Int32)))
      body, start_line = route_body(lines, route_index)
      if body.empty?
        body, start_line = named_handler_body(lines[route_index], handler_bodies, route_index)
      end
      return if body.empty?

      callees = Noir::SwiftCalleeExtractor.callees_for_body(body, path, start_line)
      Noir::SwiftCalleeExtractor.attach_to(endpoint, callees)
    end

    private def route_body(lines : Array(String), route_index : Int32) : Tuple(String, Int32)
      route_line = lines[route_index]
      opening_brace = route_line.index('{')
      return {"", route_index + 2} unless opening_brace

      first_fragment = route_line[(opening_brace + 1)..]? || ""
      clean_fragment, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first_fragment, 0, false)
      body_lines = [] of String
      brace_count = 1 + clean_fragment.count('{') - clean_fragment.count('}')

      if brace_count <= 0
        closing_brace = clean_fragment.rindex('}')
        first_fragment = first_fragment[0...closing_brace] if closing_brace
        return {first_fragment, route_index + 1}
      end

      body_lines << first_fragment
      index = route_index + 1

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
            body_lines << line
          end
          break
        end

        body_lines << line
        brace_count = next_brace_count

        index += 1
      end

      {body_lines.join("\n"), route_index + 1}
    end

    private def route_parts(line : String) : Tuple(String, String, String)?
      return unless route_definition_line?(line)

      if match = line.match(ON_ROUTE_PATTERN)
        return {match[1], match[2], match[3]}
      end

      if match = line.match(ROUTE_PATTERN)
        return {match[1], match[2].upcase, match[3]}
      end

      nil
    end

    private def register_group_assignment(line : String, prefix_by_receiver : Hash(String, String))
      match = line.match(GROUP_ASSIGN_PATTERN)
      return unless match

      variable = match[1]
      base = match[2]
      prefix = parse_route_path(match[3])
      prefix_by_receiver[variable] = join_paths(prefix_for_receiver(base, prefix_by_receiver), prefix)
    end

    private def register_group_closure(line : String,
                                       prefix_by_receiver : Hash(String, String),
                                       group_prefix_stack : Array(Tuple(String, Int32)),
                                       brace_depth : Int32)
      match = line.match(GROUP_CLOSURE_PATTERN)
      return unless match

      base = match[1]
      args = match[2]
      variable = match[3]
      prefix_by_receiver[variable] = join_paths(prefix_for_receiver(base, prefix_by_receiver), parse_route_path(args))
      group_prefix_stack << {variable, brace_depth + 1}
    end

    private def update_group_depth(line : String,
                                   brace_depth : Int32,
                                   group_prefix_stack : Array(Tuple(String, Int32)),
                                   prefix_by_receiver : Hash(String, String)) : Int32
      structural, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, 0, false)
      depth = brace_depth + structural.count('{') - structural.count('}')

      while !group_prefix_stack.empty? && depth < group_prefix_stack.last[1]
        variable, _ = group_prefix_stack.pop
        prefix_by_receiver.delete(variable)
      end

      depth
    end

    private def prefix_for_receiver(receiver : String, prefix_by_receiver : Hash(String, String)) : String
      receiver.split('.').reverse_each do |part|
        if prefix = prefix_by_receiver[part]?
          return prefix
        end
      end

      ""
    end

    private def join_paths(prefix : String, path : String) : String
      return normalize_path(path) if prefix.empty? || prefix == "/"
      return normalize_path(prefix) if path.empty? || path == "/"

      "#{normalize_path(prefix).rstrip("/")}/#{path.lstrip("/")}"
    end

    private def normalize_path(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized.gsub(%r{/+}, "/")
    end

    private def code_line(line : String) : String
      line.split("//", 2).first
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
      # Extract query parameters from req.query
      if line.includes?("req.query[") || line.includes?("req.query.get(")
        match = line.match(/req\.query\[["']([^"']+)["']\]/) ||
                line.match(/req\.query\.get\(["']([^"']+)["']\)/)
        if match
          query_name = match[1]
          endpoint.push_param(Param.new(query_name, "", "query"))
        end
      end

      # Extract body parameters from req.content.decode
      if line.includes?("req.content.decode(") || line.includes?("try req.content.decode")
        endpoint.push_param(Param.new("body", "", "json"))
      end

      # Extract headers from req.headers
      if line.includes?("req.headers[")
        match = line.match(/req\.headers\[["']([^"']+)["']\]/)
        if match
          header_name = match[1]
          endpoint.push_param(Param.new(header_name, "", "header"))
        end
      end

      # Extract cookies from req.cookies
      if line.includes?("req.cookies[")
        match = line.match(/req\.cookies\[["']([^"']+)["']\]/)
        if match
          cookie_name = match[1]
          endpoint.push_param(Param.new(cookie_name, "", "cookie"))
        end
      end

      # Extract path parameters from req.parameters.get
      if line.includes?("req.parameters.get(")
        match = line.match(/req\.parameters\.get\(["']([^"']+)["']\)/)
        if match
          param_name = match[1]
          if !existing_path_params.includes?(param_name)
            endpoint.push_param(Param.new(param_name, "", "path"))
            existing_path_params.add(param_name)
          end
        end
      end
    end

    private def named_handler_body(route_line : String,
                                   handler_bodies : Hash(String, Tuple(String, Int32)),
                                   route_index : Int32) : Tuple(String, Int32)
      handler_name = route_handler_name(route_line)
      return {"", route_index + 2} unless handler_name

      handler_bodies[handler_name]? || {"", route_index + 2}
    end

    private def route_handler_name(route_line : String) : String?
      stripped, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(route_line, 0, false)
      if match = stripped.match(/\buse:\s*([A-Za-z_]\w*)/)
        return match[1]
      end

      nil
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

    private def body_after_opening_brace(lines : Array(String), opening_index : Int32, opening_brace : Int32) : Tuple(String, Int32)
      route_line = lines[opening_index]
      first_fragment = route_line[(opening_brace + 1)..]? || ""
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
        next_brace_count = brace_count + stripped.count('{') - stripped.count('}')

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
  end
end
