require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class AspNetMvc < Analyzer
    analyzer_for "cs_aspnet_mvc"

    include Common

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The attribute set is fixed, so precompile
    # the route-extraction matchers once at load time.
    ATTRIBUTE_ROUTE_PATTERNS = ["HttpGet", "HttpPost", "HttpPut", "HttpDelete", "HttpPatch", "Route"].to_h do |attribute|
      {attribute, /\b#{attribute}\s*\(\s*"([^"]+)"/}
    end

    def analyze
      include_callee = callees_needed?
      # Every project in the scan can carry its own App_Start/RouteConfig.cs.
      CodeLocator.instance.all(Noir::LocatorKeys::CS_APINET_MVC_ROUTECONFIG).uniq.each do |route_config_path|
        analyze_route_config(route_config_path) if File.exists?(route_config_path)
      end

      # Analyze controller files for action methods and parameters
      analyze_controllers(include_callee)

      @result
    end

    private def analyze_route_config(route_config_path : String)
      maproute_check = false
      maproute_buffer = ""
      maproute_line = 0

      read_file_content(route_config_path).each_line.with_index do |line, index|
        if line.includes? ".MapRoute("
          maproute_check = true
          maproute_buffer = line
          maproute_line = index + 1
        end

        if line.includes? ");"
          maproute_check = false
          unless maproute_buffer.empty?
            buffer = maproute_buffer.gsub(/[\r\n]/, "")
            buffer = buffer.gsub(/\s+/, "")
            buffer.split(",").each do |item|
              if item.includes? "url:"
                url = item.gsub(/url:/, "").gsub(/"/, "")
                details = Details.new(PathInfo.new(route_config_path, maproute_line))
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

    private def analyze_controllers(include_callee : Bool)
      controller_files = get_files_by_extension(".cs").select do |file|
        next false if Common.csharp_test_path?(base_relative_path(file))
        file.includes?("Controller") && !File.basename(file).includes?("RouteConfig")
      end

      controller_files.each do |file|
        analyze_controller_file(file, include_callee)
      end
    end

    private def analyze_controller_file(file : String, include_callee : Bool)
      return unless File.exists?(file)

      content = read_file_content(file)
      return unless content.includes?("Controller") && content.includes?("Result")
      return if Common.aspnet_core_source?(content)
      web_api_file = !content.includes?("System.Web.Mvc") && content.matches?(WEB_API_NAMESPACE_RE)

      # Comment-blanked, so a commented-out attribute or parameter is not read.
      lexer = Noir::CSharpLexer.new(content)
      lines = lexer.code_lines
      masked_lines = lexer.masked_lines

      i = 0
      http_method = "GET" # Default method for tracking across lines
      action_route = ""   # Track action-level route
      explicit_endpoint_attribute = false
      # Open class bodies, innermost last: {body depth, controller name or nil
      # for a non-controller class, route prefix}. A file can declare several
      # controllers, and each action belongs to the class it sits in.
      scopes = [] of Tuple(Int32, String?, String)
      pending_class : Tuple(Int32, String?, String)? = nil
      depth = 0

      while i < lines.size
        start_index = i
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

        if class_match = CLASS_DECL_RE.match(masked_lines[i])
          base = class_match[2]? || masked_lines[i + 1]?.try { |next_line| BASE_LIST_LINE_RE.match(next_line).try(&.[1]) }
          before = class_match.pre_match
          body_depth = depth + before.count('{') - before.count('}') + 1
          scope = {body_depth, controller_class_name(class_match[1], base, web_api_file), controller_route_prefix(lines, masked_lines, i)}
          # A body opened on the class line can hold an action on that line.
          if class_match.post_match.includes?('{')
            scopes << scope
            pending_class = nil
          else
            pending_class = scope
          end
          # Attributes above the class (`[RoutePrefix]`) are not an action's.
          http_method = "GET"
          action_route = ""
          explicit_endpoint_attribute = false
        end

        # Check for action method definition
        _, controller_name, controller_prefix = scopes.last? || {0, nil, ""}
        if controller_name && line.includes?("public") && line.includes?("(") &&
           (line.matches?(ACTION_RESULT_RE) || explicit_endpoint_attribute)
          signature, end_index = build_signature(lines, masked_lines, i)
          action_name = extract_action_name(signature)
          parameters = extract_parameters(signature, http_method)

          unless action_name.empty?
            # Build URL from controller route, action route, and action name
            url = build_url(controller_prefix, action_route, controller_name, action_name)
            details = Details.new(PathInfo.new(file, i + 1))
            endpoint = Endpoint.new(url, http_method, details)

            parameters.each do |param|
              endpoint.params << param
            end

            # Unlike aspnet_core_mvc, this analyzer parses params from the
            # signature only, so `body_block` exists purely to feed callee
            # extraction — skip building it on the default scan path where
            # `attach_csharp_callees` is a no-op anyway (`include_callee`
            # false).
            if include_callee
              body_block = extract_method_block(lines, masked_lines, end_index)
              attach_csharp_callees(endpoint, body_block, file, end_index + 1, include_callee, skip_first_line: true)
            end
            @result << endpoint

            # Reset to default after processing the method
            http_method = "GET"
            action_route = ""
            explicit_endpoint_attribute = false
          end
          i = end_index
        end

        (start_index..i).each do |index|
          depth += masked_lines[index].count('{') - masked_lines[index].count('}')
        end
        if (pending = pending_class) && depth >= pending[0]
          scopes << pending
          pending_class = nil
        end
        while (open = scopes.last?) && depth < open[0]
          scopes.pop
        end

        i += 1
      end
    end

    CLASS_DECL_RE = /\bclass\s+(\w+)(?:\s*<[^>]*>)?\s*(?::\s*([\w.]+))?/
    # The return type ends in `Result` right before the action name:
    # `ActionResult`, `JsonResult`, `FileResult`, `Task<ViewResult>`, ...
    ACTION_RESULT_RE = /Result\s*>?\s+\w+\s*\(/
    # A base list wrapped onto the line after the class name.
    BASE_LIST_LINE_RE = /\A\s*:\s*([\w.]+)/

    WEB_API_NAMESPACE_RE = /\bSystem\.Web\.(?:Http|OData)\b/

    # MVC 5 takes any `*Controller` class with a base list (`: Controller`,
    # `: BaseController`, ...). Web API 2 controllers (`ApiController`,
    # OData, and local bases over them in a file that imports Web API but not
    # MVC) route by verb convention, which this analyzer does not model.
    private def controller_class_name(name : String, base : String?, web_api_file : Bool) : String?
      return unless base && name.ends_with?("Controller") && name != "Controller"
      base_name = base.split('.').last
      return if base_name == "ApiController"
      return if web_api_file && base_name != "Controller"
      name.rchop("Controller")
    end

    ROUTE_PREFIX_ATTR_RE = /\[\s*RoutePrefix\s*\(\s*"([^"]+)"/
    ROUTE_ATTR_RE        = /\[\s*Route\s*\(\s*"([^"]+)"/

    # `[RoutePrefix("x")]` (else a class-level `[Route("x")]`) on the class
    # line or the attribute lines directly above it.
    private def controller_route_prefix(lines : Array(String), masked_lines : Array(String), index : Int32) : String
      route = nil
      j = index
      while j >= 0 && (j == index || attribute_only_line?(masked_lines[j]))
        if match = ROUTE_PREFIX_ATTR_RE.match(lines[j])
          return match[1]
        end
        route ||= ROUTE_ATTR_RE.match(lines[j]).try(&.[1])
        j -= 1
      end
      route || ""
    end

    private def attribute_only_line?(masked : String) : Bool
      stripped = masked.strip
      stripped.starts_with?('[') && stripped.ends_with?(']')
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
        parts = param_def.sub(/\s*=.*/m, "").split(/\s+/)
        next if parts.size < 2

        param_name = parts[-1]

        parameters << Param.new(param_name, "", param_type)
      end

      parameters
    end

    private def extract_attribute_route(line : String, attribute : String) : String
      # Extract route from [HttpGet("route")] or [Route("route")]. The
      # attribute's own parens only: in `[HttpPost, ActionName("Delete")]`
      # the literal belongs to ActionName. `[HttpGet, Route("x")]` still
      # routes through its Route.
      attribute_regex = ATTRIBUTE_ROUTE_PATTERNS[attribute]? || /\b#{attribute}\s*\(\s*"([^"]+)"/
      match = line.match(attribute_regex) || line.match(ATTRIBUTE_ROUTE_PATTERNS["Route"])
      return "" unless match
      match[1]
    end

    private def build_url(controller_route : String, action_route : String, controller_name : String, action_name : String) : String
      # `[Route("~/x")]` is app-rooted: it overrides the `[RoutePrefix]`.
      if action_route.starts_with?("~/")
        controller_route = ""
        action_route = action_route.lchop('~')
      end

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
