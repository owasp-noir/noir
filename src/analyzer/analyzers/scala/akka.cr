require "../../engines/scala_engine"

module Analyzer::Scala
  class Akka < ScalaEngine
    HTTP_METHODS = %w[get post put delete patch head options]

    def analyze_file(path : String) : Array(Endpoint)
      content = File.read(path)
      extract_routes_from_content(path, content, any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?))
    end

    # Extract routes from Akka HTTP DSL
    private def extract_routes_from_content(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = content.split('\n')
      prefix_stack = [] of String
      brace_depth = 0
      prefix_depths = [] of Int32 # Track at which depth each prefix was added

      lines.each_with_index do |line, index|
        stripped_line = scala_code_line(line).strip
        structural_line = scala_structural_line(line).strip

        # Handle pathPrefix: pathPrefix("api" / "v1") { ... }
        if path_prefix_args = directive_args(stripped_line, "pathPrefix")
          prefix = akka_path_from_args(path_prefix_args, path_param_names(stripped_line))
          prefix_stack.push(prefix)
          # Record the depth at which this prefix was added (after we count the opening brace)
          prefix_depths.push(brace_depth + 1)
        end

        # Handle path with potential matchers: path("users" / IntNumber) { userId => ... }
        if path_args = directive_args(stripped_line, "path")
          route_path = akka_path_from_args(path_args, path_param_names(stripped_line))

          # Build full path with prefix
          full_path = join_paths(prefix_stack, route_path)

          # Find HTTP methods in the following lines within the same block
          block = extract_block_from_index(lines, index)
          next unless block

          block_content = block[0]
          block_end = block[2]

          HTTP_METHODS.each do |method|
            if block_content =~ /\b#{method}\s*\{/
              endpoint = create_endpoint(full_path, method.upcase, path)

              extract_path_params(endpoint, full_path)

              # Extract additional parameters from the block
              extract_params_from_block(endpoint, block_content)
              attach_method_callees(endpoint, lines, index, block_end, method, path) if include_callee

              endpoints << endpoint
            end
          end
        end

        if stripped_line.includes?("pathEnd") || stripped_line.includes?("pathEndOrSingleSlash")
          full_path = prefix_stack.empty? ? "/" : prefix_stack.join("")
          block = extract_block_from_index(lines, index)
          next unless block

          block_content = block[0]
          block_end = block[2]

          HTTP_METHODS.each do |method|
            if block_content =~ /\b#{method}\s*\{/
              endpoint = create_endpoint(full_path, method.upcase, path)
              extract_path_params(endpoint, full_path)
              extract_params_from_block(endpoint, block_content)
              attach_method_callees(endpoint, lines, index, block_end, method, path) if include_callee
              endpoints << endpoint
            end
          end
        end

        # Track brace depth to manage prefix stack
        opening_braces = structural_line.count('{')
        closing_braces = structural_line.count('}')

        brace_depth += opening_braces
        brace_depth -= closing_braces

        # Pop prefixes when we exit their depth level
        while !prefix_depths.empty? && brace_depth < prefix_depths.last
          prefix_stack.pop
          prefix_depths.pop
        end
      end

      endpoints
    end

    # Extract block content starting from a given index
    private def extract_block_from_index(lines : Array(String), start_index : Int32) : Tuple(String, Int32, Int32)?
      extract_scala_brace_block_with_end(lines, start_index)
    end

    private def attach_method_callees(endpoint : Endpoint,
                                      lines : Array(String),
                                      route_start : Int32,
                                      route_end : Int32,
                                      method : String,
                                      path : String)
      extract_method_blocks(lines, route_start, route_end, method).each do |body, start_line|
        callees = Noir::ScalaCalleeExtractor.callees_for_body(body, path, start_line)
        attach_scala_callees(endpoint, callees)
      end
    end

    private def extract_method_blocks(lines : Array(String),
                                      route_start : Int32,
                                      route_end : Int32,
                                      method : String) : Array(Tuple(String, Int32))
      blocks = [] of Tuple(String, Int32)
      index = route_start

      while index <= route_end
        stripped = scala_structural_line(lines[index])
        match = stripped.match(/(?<![.\w])#{Regex.escape(method)}\s*\{/)
        unless match
          index += 1
          next
        end

        opening_brace = (match.end(0) || 1) - 1
        if block = extract_scala_brace_block_with_end_at(lines, index, opening_brace)
          blocks << {block[0], block[1]}
          index = block[2] + 1
          next
        end

        index += 1
      end

      blocks
    end

    # Extract parameters from a code block
    private def extract_params_from_block(endpoint : Endpoint, block : String)
      # Extract single parameter: parameter("name") { ... }
      block.scan(/parameter\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      # Extract multiple parameters: parameters("name", "age") or parameters("name", "age".optional)
      if params_match = block.match(/parameters\s*\(([^)]+)\)/)
        params_content = params_match[1]
        params_content.scan(/['"](\w+)['"]/) do |match|
          param_name = match[1]
          # Avoid duplicating parameters already added
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end
      end

      # Extract request body: entity(as[User]) { ... }
      if entity_match = block.match(/entity\s*\(\s*as\[([^\]]+)\]/)
        endpoint.push_param(Param.new("body", entity_match[1], "json"))
      end

      # Extract headers: headerValueByName("Authorization") { ... }
      block.scan(/headerValueByName\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "header"))
      end

      # Extract optional headers: optionalHeaderValueByName("X-API-Key") { ... }
      block.scan(/optionalHeaderValueByName\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
    end

    private def directive_args(line : String, directive : String) : String?
      match = line.match(/(?<![.\w])#{Regex.escape(directive)}\s*\(([^)]*)\)/)
      return unless match

      match[1]
    end

    private def akka_path_from_args(args : String, param_names : Array(String)) : String
      segments = [] of String
      param_index = 0

      args.scan(/"([^"]+)"|(IntNumber|LongNumber|Segment|Remaining|JavaUUID)/) do |match|
        if literal = match[1]?
          segments.concat(literal.split('/').reject(&.empty?))
        elsif match[2]?
          param_name = param_names[param_index]? || default_param_name(param_index)
          segments << "{#{param_name}}"
          param_index += 1
        end
      end

      return "/" if segments.empty?

      "/#{segments.join("/")}"
    end

    private def default_param_name(index : Int32) : String
      index == 0 ? "id" : "id#{index + 1}"
    end

    private def path_param_names(line : String) : Array(String)
      match = line.match(/\{\s*\(?\s*([^=]+?)\s*\)?\s*=>/)
      return [] of String unless match

      match[1].split(',').map(&.strip).reject(&.empty?)
    end

    private def join_paths(prefix_stack : Array(String), route_path : String) : String
      parts = prefix_stack + [route_path]
      normalized = parts.join("").gsub(%r{/+}, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    private def extract_path_params(endpoint : Endpoint, route_path : String)
      route_path.scan(/\{(\w+)\}/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String)
      details = Details.new(PathInfo.new(source, 0))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
