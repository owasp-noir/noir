require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class AspNetMvc < Analyzer
    include Common

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?)
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
      analyze_controllers(include_callee)

      @result
    end

    private def analyze_controllers(include_callee : Bool)
      controller_files = get_files_by_extension(".cs").select do |file|
        file.includes?("Controller") && !file.includes?("RouteConfig")
      end

      controller_files.each do |file|
        analyze_controller_file(file, include_callee)
      end
    end

    private def analyze_controller_file(file : String, include_callee : Bool)
      return unless File.exists?(file)

      content = File.read(file, encoding: "utf-8", invalid: :skip)
      return unless content.includes?("Controller") && content.includes?("ActionResult")

      lines = content.lines
      controller_name = extract_controller_name(content)
      return if controller_name.empty?

      # Extract controller-level route prefix
      controller_route_prefix = extract_controller_route(content)

      i = 0
      http_method = "GET" # Default method for tracking across lines
      action_route = ""   # Track action-level route

      while i < lines.size
        line = lines[i]

        # Look for HTTP method attributes (with optional route)
        if line.includes?("[HttpPost")
          http_method = "POST"
          action_route = extract_attribute_route(line, "HttpPost")
        elsif line.includes?("[HttpGet")
          http_method = "GET"
          action_route = extract_attribute_route(line, "HttpGet")
        elsif line.includes?("[HttpPut")
          http_method = "PUT"
          action_route = extract_attribute_route(line, "HttpPut")
        elsif line.includes?("[HttpDelete")
          http_method = "DELETE"
          action_route = extract_attribute_route(line, "HttpDelete")
        elsif line.includes?("[HttpPatch")
          http_method = "PATCH"
          action_route = extract_attribute_route(line, "HttpPatch")
        elsif line.includes?("[Route")
          action_route = extract_attribute_route(line, "Route")
        end

        # Check for action method definition
        if line.includes?("public") && line.includes?("ActionResult") && line.includes?("(")
          signature, end_index = build_signature(lines, i)
          action_name = extract_action_name(signature)
          parameters = extract_parameters(signature, http_method)

          unless action_name.empty?
            # Build URL from controller route, action route, and action name
            url = build_url(controller_route_prefix, action_route, controller_name, action_name)
            details = Details.new(PathInfo.new(file, i + 1))
            endpoint = Endpoint.new(url, http_method, details)
            body_block = extract_method_block(lines, end_index)

            parameters.each do |param|
              endpoint.params << param
            end

            attach_csharp_callees(endpoint, body_block, file, end_index + 1, include_callee, skip_first_line: true)
            @result << endpoint

            # Reset to default after processing the method
            http_method = "GET"
            action_route = ""
          end
          i = end_index
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

    private def extract_parameters(full_signature : String, http_method : String) : Array(Param)
      parameters = [] of Param

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

        # Check for parameter binding attributes
        param_type = default_param_type
        if param_def.includes?("[FromQuery]")
          param_type = "query"
          param_def = param_def.gsub("[FromQuery]", "").strip
        elsif param_def.includes?("[FromRoute]")
          param_type = "path"
          param_def = param_def.gsub("[FromRoute]", "").strip
        elsif param_def.includes?("[FromBody]")
          param_type = "json"
          param_def = param_def.gsub("[FromBody]", "").strip
        elsif param_def.includes?("[FromHeader]")
          param_type = "header"
          param_def = param_def.gsub("[FromHeader]", "").strip
        elsif param_def.includes?("[FromForm]")
          param_type = "form"
          param_def = param_def.gsub("[FromForm]", "").strip
        elsif param_def.includes?("[FromCookie]")
          param_type = "cookie"
          param_def = param_def.gsub("[FromCookie]", "").strip
        end

        # Extract parameter name (last word before optional default value)
        # Format: "type name" or "type name = default" or "[Attribute] type name"
        parts = param_def.split(/\s+/)
        next if parts.size < 2

        param_name = parts[-1].gsub(/=.*$/, "").strip

        parameters << Param.new(param_name, "", param_type)
      end

      parameters
    end

    private def extract_controller_route(content : String) : String
      # Extract [Route("...")] attribute from controller class
      match = content.match(/\[Route\s*\(\s*"([^"]+)"\s*\)\s*\]\s*\n?\s*public\s+class\s+\w+Controller/)
      return "" unless match
      match[1]
    end

    private def extract_attribute_route(line : String, attribute : String) : String
      # Extract route from [HttpGet("route")] or [Route("route")]
      match = line.match(/\[#{attribute}\s*\(\s*"([^"]+)"\s*\)\s*\]/)
      return "" unless match
      match[1]
    end

    private def build_url(controller_route : String, action_route : String, controller_name : String, action_name : String) : String
      # Build URL from components
      parts = [] of String

      # Add controller route if present
      unless controller_route.empty?
        # Replace [controller] placeholder
        route = controller_route.gsub("[controller]", controller_name)
        parts << route unless route.empty?
      end

      # Add action route if present
      if action_route.empty?
        # If no explicit route, use controller and action names
        if controller_route.empty?
          parts << controller_name
        end
        parts << action_name
      else
        parts << action_route
      end

      # Join parts and ensure it starts with /
      url = "/" + parts.join("/").gsub(/\/+/, "/").gsub(/^\//, "")
      url = "/" if url.empty?
      url
    end
  end
end
