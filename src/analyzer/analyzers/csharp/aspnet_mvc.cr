require "../../../models/analyzer"

module Analyzer::CSharp
  class AspNetMvc < Analyzer
    def analyze
      # Static Analysis
      locator = CodeLocator.instance
      route_config_file = locator.get("cs-apinet-mvc-routeconfig")

      # Analyze RouteConfig.cs for route definitions
      if File.exists?("#{route_config_file}")
        File.open("#{route_config_file}", "r", encoding: "utf-8", invalid: :skip) do |file|
          maproute_check = false
          maproute_buffer = ""

          file.each_line.with_index do |line, index|
            if line.includes? ".MapRoute("
              maproute_check = true
              maproute_buffer = line
            end

            if line.includes? ");"
              maproute_check = false
              if maproute_buffer != ""
                buffer = maproute_buffer.gsub(/[\r\n]/, "")
                buffer = buffer.gsub(/\s+/, "")
                buffer.split(",").each do |item|
                  if item.includes? "url:"
                    url = item.gsub(/url:/, "").gsub(/"/, "")
                    details = Details.new(PathInfo.new(route_config_file, index + 1))
                    @result << Endpoint.new("/#{url}", "GET", details)
                  end
                end

                maproute_buffer = ""
              end
            end

            if maproute_check
              maproute_buffer += line
            end
          end
        end
      end

      # Analyze controller files for action methods and parameters
      analyze_controllers()

      @result
    end

    private def analyze_controllers
      controller_files = get_files_by_extension(".cs").select do |file|
        file.includes?("Controller") && !file.includes?("RouteConfig")
      end

      controller_files.each do |file|
        analyze_controller_file(file)
      end
    end

    private def analyze_controller_file(file : String)
      return unless File.exists?(file)

      content = File.read(file, encoding: "utf-8", invalid: :skip)
      return unless content.includes?("Controller") && content.includes?("ActionResult")

      lines = content.lines
      controller_name = extract_controller_name(content)
      return if controller_name.empty?

      i = 0
      http_method = "GET" # Default method for tracking across lines

      while i < lines.size
        line = lines[i]

        # Look for HTTP method attributes
        if line.includes?("[HttpPost]")
          http_method = "POST"
        elsif line.includes?("[HttpGet]")
          http_method = "GET"
        elsif line.includes?("[HttpPut]")
          http_method = "PUT"
        elsif line.includes?("[HttpDelete]")
          http_method = "DELETE"
        elsif line.includes?("[HttpPatch]")
          http_method = "PATCH"
        end

        # Check for action method definition
        if line.includes?("public") && line.includes?("ActionResult") && line.includes?("(")
          action_name = extract_action_name(line)
          parameters = extract_parameters(line, lines, i, http_method)

          unless action_name.empty?
            url = "/#{controller_name}/#{action_name}"
            details = Details.new(PathInfo.new(file, i + 1))
            endpoint = Endpoint.new(url, http_method, details)

            parameters.each do |param|
              endpoint.params << param
            end

            @result << endpoint

            # Reset to default after processing the method
            http_method = "GET"
          end
        end

        i += 1
      end
    end

    private def extract_controller_name(content : String) : String
      # Extract controller class name
      match = content.match(/class\s+(\w+)Controller\s*:\s*Controller/)
      return "" unless match
      match[1]
    end

    private def extract_action_name(line : String) : String
      # Extract method name from: public ActionResult MethodName(params)
      match = line.match(/public\s+\w+\s+(\w+)\s*\(/)
      return "" unless match
      match[1]
    end

    private def extract_parameters(line : String, lines : Array(String), start_index : Int32, http_method : String) : Array(Param)
      parameters = [] of Param

      # Extract parameters from method signature
      # Handle multi-line method signatures
      full_signature = line
      paren_count = line.count('(') - line.count(')')

      current_index = start_index + 1
      while paren_count > 0 && current_index < lines.size
        full_signature += " " + lines[current_index]
        paren_count += lines[current_index].count('(') - lines[current_index].count(')')
        current_index += 1
      end

      # Extract parameter list from signature
      match = full_signature.match(/\((.*?)\)/)
      return parameters unless match

      param_list = match[1].strip
      return parameters if param_list.empty?

      # Determine default parameter type based on HTTP method
      default_param_type = case http_method
                           when "GET"
                             "query"
                           when "POST", "PUT", "PATCH"
                             "form"
                           when "DELETE"
                             "query"
                           else
                             "query"
                           end

      # Parse individual parameters
      param_list.split(',').each do |param_def|
        param_def = param_def.strip
        next if param_def.empty?

        # Extract parameter name (last word before optional default value)
        # Format: "type name" or "type name = default"
        parts = param_def.split(/\s+/)
        next if parts.size < 2

        param_name = parts[-1].gsub(/=.*$/, "").strip

        parameters << Param.new(param_name, "", default_param_type)
      end

      parameters
    end
  end
end
