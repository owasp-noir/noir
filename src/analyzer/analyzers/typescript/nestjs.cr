require "../../../models/analyzer"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  class Nestjs < Analyzer
    def analyze
      channel = Channel(String).new
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          worker_count = @options["concurrency"].to_s.to_i
          worker_count = 16 if worker_count > 16
          worker_count = 1 if worker_count < 1
          worker_count.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next unless [".ts", ".tsx"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    analyze_nestjs_file(path, result, static_dirs)
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue Exception
                  logger.debug "Error processing file #{path}: #{e.message}"
                end
              end
            end
          end
        end
      rescue Exception
        logger.debug "Channel or wait group error: #{e.message}"
      end

      # Process static directories to create endpoints for static files
      process_static_dirs(static_dirs, result)

      result
    end

    # Process static directories and add endpoints for each file
    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      static_dirs.each do |dir|
        full_path = (base_path + "/" + dir["file_path"]).gsub_repeatedly("//", "/")
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        get_files_by_prefix(full_path).each do |file_path|
          if File.exists?(file_path)
            # Use lchop to only remove from the beginning of the string
            relative_path = file_path.starts_with?(full_path) ? file_path.lchop(full_path) : file_path
            url = static_path == "/" ? relative_path : "#{static_path}#{relative_path}"
            url = "/#{url}" unless url.starts_with?("/")

            details = Details.new(PathInfo.new(file_path))
            endpoint = Endpoint.new(url, "GET", details)
            result << endpoint unless result.any? { |e| e.url == url && e.method == "GET" }
          end
        end
      end
    end

    private def analyze_nestjs_file(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)))
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Extract static paths
        Noir::JSRouteExtractor.extract_static_paths(content).each do |static_path|
          static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
        end

        analyze_nestjs_controllers(content, path, result)
      end
    rescue Exception
      logger.debug "Error analyzing NestJS file #{path}: #{e.message}"
    end

    private def analyze_nestjs_controllers(content : String, path : String, result : Array(Endpoint))
      # Split content by controllers and process each separately
      controllers = extract_controllers(content)

      controllers.each do |controller_info|
        base_path = controller_info[:base_path]
        controller_content = controller_info[:content]

        process_http_methods(controller_content, base_path, path, result)
      end
    end

    private def extract_controllers(content : String)
      controllers = [] of Hash(Symbol, String)

      # Find all @Controller decorators and their associated class content
      lines = content.split("\n")
      current_controller : Hash(Symbol, String)? = nil
      brace_count = 0
      in_class = false

      lines.each do |line|
        # Check for @Controller decorator
        if line =~ /@Controller\s*\(\s*['"`]([^'"`]*?)['"`]\s*\)/
          controller_path = $1
          current_controller = {
            :base_path => controller_path,
            :content   => "",
          }
        end

        # Check for class start after @Controller
        if current_controller && line =~ /export\s+class\s+\w+/
          in_class = true
          brace_count = 0
        end

        # Count braces to find class end
        if in_class && current_controller
          brace_count += line.count('{')
          brace_count -= line.count('}')

          current_controller[:content] = current_controller[:content] + line + "\n"

          # End of class
          if brace_count == 0 && line.includes?('}')
            controllers << current_controller
            current_controller = nil
            in_class = false
          end
        end
      end

      controllers
    end

    private def process_http_methods(class_content : String, base_path : String, file_path : String, result : Array(Endpoint))
      http_methods = ["Get", "Post", "Put", "Delete", "Patch", "Options", "Head"]

      http_methods.each do |method|
        method_pattern = /@#{method}\s*\(\s*(?:['"`]([^'"`]*?)['"`]\s*)?\)/

        class_content.scan(method_pattern) do |match|
          route_path = ""
          if match.size > 1 && match[1]?
            route_path = match[1]
          end

          # Construct full URL path
          full_path = combine_paths(base_path, route_path)

          # Create endpoint
          endpoint = Endpoint.new(full_path, method.upcase)
          endpoint.details = Details.new(PathInfo.new(file_path, 1))

          # Extract path parameters from URL
          extract_path_parameters(full_path, endpoint)

          # Extract parameters from the method area
          if match.begin
            extract_method_parameters(class_content, match.begin + match[0].size, endpoint)
          end

          result << endpoint
        end
      end
    end

    private def extract_method_parameters(content : String, start_pos : Int32, endpoint : Endpoint)
      # Find the method signature that immediately follows the decorator
      method_section = content[start_pos..-1]

      # Look for the method name first
      method_name_match = method_section.match(/\s*(\w+)\s*\(/)

      if method_name_match
        start_paren = method_name_match.end

        # Find the matching closing parenthesis for the method parameters
        paren_count = 1
        end_paren = start_paren
        method_section[start_paren..-1].each_char_with_index do |char, index|
          case char
          when '('
            paren_count += 1
          when ')'
            paren_count -= 1
            if paren_count == 0
              end_paren = start_paren + index
              break
            end
          end
        end

        if end_paren > start_paren
          method_params = method_section[start_paren...end_paren]
          extract_decorator_parameters(method_params, endpoint)
        end
      end
    end

    private def extract_decorator_parameters(method_params : String, endpoint : Endpoint)
      # Extract @Query parameters
      method_params.scan(/@Query\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end

      # Extract @Param parameters (path parameters)
      method_params.scan(/@Param\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end

      # Extract @Body() - indicates request body
      if method_params.includes?("@Body()")
        endpoint.push_param(Param.new("body", "", "body"))
      end

      # Extract @Headers parameters
      method_params.scan(/@Headers\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "header"))
        end
      end
    end

    private def combine_paths(base : String, route : String) : String
      return route if base.empty?
      return base if route.empty?

      base = base.chomp("/")
      route = route.starts_with?("/") ? route : "/#{route}"

      "#{base}#{route}"
    end

    private def extract_path_parameters(url : String, endpoint : Endpoint)
      # Extract path parameters from URL patterns like :id
      url.scan(/:(\w+)/) do |match|
        if match.size > 0
          param_name = match[1]
          # Only add if not already added by @Param decorator
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
      end
    end
  end
end
