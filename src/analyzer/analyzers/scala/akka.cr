require "../../../models/analyzer"

module Analyzer::Scala
  class Akka < Analyzer
    SCALA_EXTENSION = "scala"
    HTTP_METHODS    = %w[get post put delete patch head options]

    def analyze
      file_list = get_all_files()
      file_list.each do |path|
        next unless File.exists?(path)

        if path.ends_with?(".#{SCALA_EXTENSION}")
          process_scala_file(path)
        end
      end

      Fiber.yield
      @result
    end

    # Process individual Scala files to analyze Akka HTTP routing
    private def process_scala_file(path : String)
      content = File.read(path)
      extract_routes_from_content(path, content)
    end

    # Extract routes from Akka HTTP DSL
    private def extract_routes_from_content(path : String, content : String)
      lines = content.split('\n')
      prefix_stack = [] of String
      
      lines.each_with_index do |line, index|
        stripped_line = line.strip
        
        # Handle pathPrefix: pathPrefix("api") { ... }
        if path_prefix_match = stripped_line.match(/pathPrefix\s*\(\s*"([^"]+)"\s*\)\s*\{/)
          prefix = path_prefix_match[1]
          prefix = "/#{prefix}" unless prefix.starts_with?("/")
          prefix_stack.push(prefix)
          next
        end
        
        # Track closing braces to manage prefix stack
        closing_braces = stripped_line.count('}')
        opening_braces = stripped_line.count('{')
        net_braces = closing_braces - opening_braces
        
        if net_braces > 0
          net_braces.times do
            prefix_stack.pop if !prefix_stack.empty?
          end
        end
        
        # Handle path with potential matchers: path("users" / IntNumber) { userId => ... }
        if path_match = stripped_line.match(/path\s*\(\s*"([^"]+)"/)
          route_path = path_match[1]
          route_path = "/#{route_path}" unless route_path.starts_with?("/")
          
          # Check for path parameter matchers
          has_param = stripped_line =~ /\/\s*(IntNumber|LongNumber|Segment|Remaining|JavaUUID)/
          if has_param
            route_path = "#{route_path}/{id}"
          end
          
          # Build full path with prefix
          full_path = prefix_stack.empty? ? route_path : "#{prefix_stack.join("")}#{route_path}"
          
          # Find HTTP methods in the following lines within the same block
          block_content = extract_block_from_index(lines, index)
          
          HTTP_METHODS.each do |method|
            if block_content =~ /\b#{method}\s*\{/
              endpoint = create_endpoint(full_path, method.upcase, path)
              
              # Add path parameter if detected
              if has_param
                endpoint.push_param(Param.new("id", "", "path"))
              end
              
              # Extract additional parameters from the block
              extract_params_from_block(endpoint, block_content)
              
              @result << endpoint
            end
          end
        end
      end
    end
    
    # Extract block content starting from a given index
    private def extract_block_from_index(lines : Array(String), start_index : Int32) : String
      block_lines = [] of String
      brace_count = 0
      started = false
      
      (start_index...lines.size).each do |i|
        line = lines[i]
        
        brace_count += line.count('{')
        
        if brace_count > 0
          started = true
          block_lines << line
        end
        
        brace_count -= line.count('}')
        
        break if started && brace_count <= 0
      end
      
      block_lines.join(" ")
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

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String)
      details = Details.new(PathInfo.new(source, 0))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
