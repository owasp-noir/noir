require "../../../models/analyzer"
require "../../../minilexers/kotlin"
require "../../../miniparsers/kotlin"
require "../../../utils/utils.cr"

module Analyzer::Kotlin
  class Ktor < Analyzer
    KOTLIN_EXTENSION = "kt"
    HTTP_METHODS     = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    def analyze
      parser_map = Hash(String, KotlinParser).new

      file_list = get_all_files()
      file_list.each do |path|
        next unless File.exists?(path)

        if path.ends_with?(".#{KOTLIN_EXTENSION}")
          process_kotlin_file(path, parser_map)
        end
      end

      Fiber.yield
      @result
    end

    # Process individual Kotlin files to analyze Ktor routing
    private def process_kotlin_file(path : String, parser_map : Hash(String, KotlinParser))
      content = File.read(path)
      parser = parser_map[path]? || create_parser(Path.new(path), content)
      parser_map[path] ||= parser

      # Extract routing calls from the content
      extract_routes_from_content(path, content)
    end

    # Create a parser for the given path and content
    private def create_parser(path : Path, content : String = "") : KotlinParser
      file_content = content.empty? ? File.read(path) : content
      lexer = KotlinLexer.new
      tokens = lexer.tokenize(file_content)
      KotlinParser.new(path.to_s, tokens)
    end

    # Extract routes from Ktor routing DSL
    private def extract_routes_from_content(path : String, content : String)
      lines = content.split('\n')
      prefix_stack = [] of String
      brace_stack = [] of Int32 # Track brace depth for each prefix

      lines.each_with_index do |line, index|
        stripped_line = line.strip
        current_depth = count_brace_depth(lines[0..index])

        # Handle routing blocks: route("/api") { ... }
        if route_match = stripped_line.match(/route\s*\(\s*["']([^"']+)["']\s*\)\s*\{/)
          route_path = route_match[1]
          prefix_stack.push(route_path)
          brace_stack.push(current_depth)
          next
        end

        # Check if we've exited any nested routes by comparing brace depth
        while !brace_stack.empty? && current_depth < brace_stack.last
          prefix_stack.pop
          brace_stack.pop
        end

        # Handle HTTP method calls: get("/path") { ... }
        HTTP_METHODS.each do |method|
          if method_match = stripped_line.match(/#{method.downcase}\s*\(\s*["']([^"']+)["']\s*\)/)
            route_path = method_match[1]
            full_path = build_full_path(prefix_stack, route_path)

            endpoint = create_endpoint(full_path, method, path)

            # Extract additional parameters from the line and subsequent lines
            extract_parameters_from_context(endpoint, line, content, index)

            @result << endpoint
          end
        end
      end
    end

    # Count the current brace depth at a given line
    private def count_brace_depth(lines : Array(String)) : Int32
      depth = 0
      lines.each do |line|
        depth += line.count('{')
        depth -= line.count('}')
      end
      depth
    end

    # Build the full path by combining prefix stack and route path
    private def build_full_path(prefix_stack : Array(String), route_path : String) : String
      if prefix_stack.empty?
        route_path
      else
        combined_prefix = prefix_stack.join("")
        "#{combined_prefix}#{route_path}"
      end
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String)
      details = Details.new(PathInfo.new(source, 0))
      params = [] of Param

      # Extract path parameters from the URL
      path_params = extract_path_parameters(path)
      params.concat(path_params)

      Endpoint.new(path, method, params, details)
    end

    # Extract path parameters from URL patterns like {id} or {userId}
    private def extract_path_parameters(path : String) : Array(Param)
      params = [] of Param

      # Match {param} patterns in Ktor
      path.scan(/\{([^}]+)\}/) do |match|
        param_name = match[1]
        param = Param.new(param_name, "", "path")
        params << param
      end

      params
    end

    # Extract additional parameters from the route handler
    private def extract_parameters_from_context(endpoint : Endpoint, line : String, content : String, line_index : Int32)
      # Look for common parameter patterns in Ktor handlers
      # Search through the handler block for parameter usage
      lines = content.split('\n')

      # Find the end of the current handler block
      start_index = line_index
      brace_count = 0
      end_index = start_index

      (start_index...lines.size).each do |i|
        brace_count += lines[i].count('{')
        brace_count -= lines[i].count('}')
        if brace_count == 0 && i > start_index
          end_index = i
          break
        end
      end

      # Analyze lines within the handler block
      (start_index..end_index).each do |i|
        handler_line = lines[i]

        # Check for call.receive<Type>() patterns
        if handler_line.includes?("call.receive<") && (type_match = handler_line.match(/call\.receive<([^>]+)>/))
          param_type = type_match[1]
          param = Param.new("body", param_type, "json")
          endpoint.push_param(param)
        end

        # Check for call.parameters["name"] patterns
        if handler_line.includes?("call.parameters[")
          handler_line.scan(/call\.parameters\["([^"]+)"\]/) do |match|
            param_name = match[1]
            param = Param.new(param_name, "", "query")
            endpoint.push_param(param)
          end
        end

        # Check for call.request.headers patterns
        if handler_line.includes?("call.request.headers[")
          handler_line.scan(/call\.request\.headers\["([^"]+)"\]/) do |match|
            header_name = match[1]
            param = Param.new(header_name, "", "header")
            endpoint.push_param(param)
          end
        end
      end
    end
  end
end
