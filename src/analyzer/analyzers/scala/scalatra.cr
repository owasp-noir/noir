require "../../engines/scala_engine"

module Analyzer::Scala
  class Scalatra < ScalaEngine
    HTTP_METHODS = %w[get post put delete patch head options]

    def analyze_file(path : String) : Array(Endpoint)
      content = File.read(path)
      extract_routes_from_content(path, content, any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?))
    end

    # Extract routes from Scalatra DSL
    private def extract_routes_from_content(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = content.split('\n')

      lines.each_with_index do |line, index|
        stripped_line = scala_code_line(line).strip

        # Match Scalatra route definitions: get("/path") { ... }
        HTTP_METHODS.each do |method|
          # Match: get("/users/:id") { ... } and get("/users", operation(...)) { ... }
          # Ensure it's not a method call on an object (e.g., cookies.get)
          if route_match = stripped_line.match(/(?<![.\w])#{method}\s*\(\s*"([^"]+)"/)
            route_path = route_match[1]
            # Only process if it looks like a URL path (starts with /)
            next unless route_path.starts_with?("/")

            endpoint = create_endpoint(route_path, method.upcase, path, index + 1)

            # Extract path parameters from the route
            extract_path_params(endpoint, route_path)

            # Extract parameters from the route block
            block = extract_block_from_index(lines, index)
            block_content = block ? block[0] : ""
            extract_params_from_block(endpoint, block_content)
            attach_route_callees(endpoint, block_content, path, block[1]) if include_callee && block

            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    # Extract path parameters from the route pattern
    private def extract_path_params(endpoint : Endpoint, route_path : String)
      # Match :param style parameters
      route_path.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end

      # Match *splat parameters (even without name)
      if route_path.includes?("*")
        # Scalatra uses "splat" as the default name for wildcard parameters
        endpoint.push_param(Param.new("splat", "", "path"))
      end
    end

    # Extract block content starting from a given index
    private def extract_block_from_index(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      extract_scala_brace_block(lines, start_index)
    end

    private def attach_route_callees(endpoint : Endpoint, body : String, path : String, start_line : Int32)
      callees = Noir::ScalaCalleeExtractor.callees_for_body(body, path, start_line)
      attach_scala_callees(endpoint, callees)
    end

    # Extract parameters from a code block
    private def extract_params_from_block(endpoint : Endpoint, block : String)
      # Extract query parameters: params("name")
      # Note: Only add as query param if it's not already a path param
      block.scan(/params\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        param_name = match[1]
        # Check if this is already a path parameter
        is_path_param = endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
        unless is_path_param
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end
      end

      # Extract multiParams: multiParams("tags")
      # Note: Skip if it's "splat" as that's a path param
      block.scan(/multiParams\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        param_name = match[1]
        # Skip "splat" as it's a path parameter
        next if param_name == "splat"
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end

      # Extract request body: parsedBody.extract[User]
      if entity_match = block.match(/parsedBody\.extract\[([^\]]+)\]/)
        endpoint.push_param(Param.new("body", entity_match[1], "json"))
      end

      # Extract request body alternative: request.body
      if block.includes?("request.body") && !endpoint.params.any? { |p| p.name == "body" }
        endpoint.push_param(Param.new("body", "", "json"))
      end

      # Extract headers: request.getHeader("Authorization")
      block.scan(/request\.getHeader\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "header" }
          endpoint.push_param(Param.new(param_name, "", "header"))
        end
      end

      # Extract cookies: cookies.get("session")
      block.scan(/cookies\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "cookie" }
          endpoint.push_param(Param.new(param_name, "", "cookie"))
        end
      end
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
