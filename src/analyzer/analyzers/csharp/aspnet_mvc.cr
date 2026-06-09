require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class AspNetMvc < Analyzer
    include Common

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The attribute set is fixed, so precompile
    # the route-extraction matchers once at load time.
    ATTRIBUTE_ROUTE_PATTERNS = ["HttpGet", "HttpPost", "HttpPut", "HttpDelete", "HttpPatch", "Route"].to_h do |attribute|
      {attribute, /\[#{attribute}[^(]*\(\s*"([^"]+)"/}
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
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
              unless maproute_buffer.empty?
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
        next false if Common.csharp_test_path?(file)
        file.includes?("Controller") && !file.includes?("RouteConfig")
      end

      controller_files.each do |file|
        analyze_controller_file(file, include_callee)
      end
    end

    private def analyze_controller_file(file : String, include_callee : Bool)
      return unless File.exists?(file)

      content = read_file_content(file)
      return unless content.includes?("Controller") && content.includes?("ActionResult")

      lines = content.lines
      masked_lines = Noir::CSharpLexer.new(content).masked_lines
      controller_name = extract_controller_name(content)
      return if controller_name.empty?

      # Extract controller-level route prefix
      controller_route_prefix = extract_controller_route(content)

      i = 0
      http_method = "GET" # Default method for tracking across lines
      action_route = ""   # Track action-level route
      explicit_endpoint_attribute = false

      while i < lines.size
        line = lines[i]

        # Look for HTTP method attributes (with optional route)
        if line.includes?("[HttpPost")
          http_method = "POST"
          action_route = extract_attribute_route(line, "HttpPost")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpGet")
          http_method = "GET"
          action_route = extract_attribute_route(line, "HttpGet")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpPut")
          http_method = "PUT"
          action_route = extract_attribute_route(line, "HttpPut")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpDelete")
          http_method = "DELETE"
          action_route = extract_attribute_route(line, "HttpDelete")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpPatch")
          http_method = "PATCH"
          action_route = extract_attribute_route(line, "HttpPatch")
          explicit_endpoint_attribute = true
        elsif line.includes?("[Route")
          action_route = extract_attribute_route(line, "Route")
          explicit_endpoint_attribute = true
        end

        # Check for action method definition
        if line.includes?("public") && line.includes?("(") && (line.includes?("ActionResult") || explicit_endpoint_attribute)
          signature, end_index = build_signature(lines, masked_lines, i)
          action_name = extract_action_name(signature)
          parameters = extract_parameters(signature, http_method)

          unless action_name.empty?
            # Build URL from controller route, action route, and action name
            url = build_url(controller_route_prefix, action_route, controller_name, action_name)
            details = Details.new(PathInfo.new(file, i + 1))
            endpoint = Endpoint.new(url, http_method, details)
            body_block = extract_method_block(lines, masked_lines, end_index)

            parameters.each do |param|
              endpoint.params << param
            end

            attach_csharp_callees(endpoint, body_block, file, end_index + 1, include_callee, skip_first_line: true)
            @result << endpoint

            # Reset to default after processing the method
            http_method = "GET"
            action_route = ""
            explicit_endpoint_attribute = false
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
      match = line.match(/public\s+(?:async\s+)?(?:override\s+)?(?:virtual\s+)?[\w<>\[\],\s]+\s+(\w+)\s*\(/)
      return "" unless match
      match[1]
    end

    private def extract_parameters(full_signature : String, http_method : String) : Array(Param)
      parameters = [] of Param

      # Extract parameter list (paren-depth aware so a param with an inner ')'
      # — a method-call default like `id = GetDefault()` or a tuple type
      # `(int,int) pair` — isn't truncated at the first ')').
      param_list = extract_balanced_param_list(full_signature)
      return parameters unless param_list

      param_list = param_list.strip
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
      split_csharp_parameters(param_list).each do |param_def|
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
        elsif param_def.includes?("[FromServices]") || param_def.includes?("[FromKeyedServices")
          next
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
      match = content.match(/\[(?:Route|RoutePrefix)\s*\(\s*"([^"]+)"\s*\)\s*\]\s*\n?\s*public\s+class\s+\w+Controller/)
      return "" unless match
      match[1]
    end

    private def extract_attribute_route(line : String, attribute : String) : String
      # Extract route from [HttpGet("route")] or [Route("route")]
      attribute_regex = ATTRIBUTE_ROUTE_PATTERNS[attribute]? || /\[#{attribute}[^(]*\(\s*"([^"]+)"/
      match = line.match(attribute_regex)
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
