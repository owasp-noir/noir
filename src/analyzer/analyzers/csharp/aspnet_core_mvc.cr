require "../../../models/analyzer"

module Analyzer::CSharp
  class AspNetCoreMvc < Analyzer
    DEFAULT_ROUTE = "{controller=Home}/{action=Index}/{id?}"

    def analyze
      route_patterns = load_route_patterns
      analyze_controllers(route_patterns)
      analyze_route_builder_endpoints
      @result
    end

    private def analyze_route_builder_endpoints
      map_regex = /Map(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*"([^"]+)"/
      map_methods_regex = /MapMethods\s*\(\s*"([^"]+)"\s*,\s*new\s*\[\]\s*\{([^\}]+)\}/

      get_files_by_extension(".cs").each do |file|
        next unless File.exists?(file)

        lines = File.read(file, encoding: "utf-8", invalid: :skip).lines
        lines.each_with_index do |line, index|
          if (match = map_regex.match(line))
            http_method = match[1].upcase
            route = match[2]
            endpoint = build_endpoint_from_route(route, http_method, file, index + 1)
            @result << endpoint if endpoint
          end

          if (match = map_methods_regex.match(line))
            route = match[1]
            raw_methods = match[2]
            methods = raw_methods.scan(/"([A-Za-z]+)"/).map { |m| m[1]?.to_s.upcase }.reject(&.empty?).uniq
            methods.each do |http_method|
              endpoint = build_endpoint_from_route(route, http_method, file, index + 1)
              @result << endpoint if endpoint
            end
          end
        end
      end
    end

    private def load_route_patterns : Array(String)
      patterns = [] of String
      files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        base == "Program.cs" || base == "Startup.cs"
      end

      files.each do |file|
        begin
          content = File.read(file, encoding: "utf-8", invalid: :skip)
          patterns.concat(extract_route_patterns(content))
        rescue e
          logger.debug "Failed to read #{file}: #{e.message}"
        end
      end

      patterns << DEFAULT_ROUTE if patterns.empty?
      patterns.uniq
    end

    private def extract_route_patterns(content : String) : Array(String)
      patterns = [] of String

      route_regex = /Map[A-Za-z]*ControllerRoute\s*\((.*?)\)/m
      pattern_regex = /pattern\s*:\s*"([^"]+)"/m
      literal_regex = /"([^"]*\{[^}]+\}[^"]*)"/m

      content.scan(route_regex) do |match|
        call_content = match[1]? || ""

        found_pattern = false
        call_content.scan(pattern_regex) do |pattern_match|
          value = pattern_match[1]?
          patterns << value if value
          found_pattern = true
        end

        # Handle overloads like MapControllerRoute("default", "{controller=Home}/{action=Index}/{id?}")
        unless found_pattern
          call_content.scan(literal_regex) do |literal_match|
            candidate = literal_match[1]?
            patterns << candidate if candidate && !candidate.empty?
          end
        end
      end

      if content.includes?("MapDefaultControllerRoute")
        patterns << DEFAULT_ROUTE
      end

      patterns
    end

    private def analyze_controllers(route_patterns : Array(String))
      controller_files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        base.includes?("Controller") && !base.ends_with?("RouteConfig.cs") && base != "Program.cs" && base != "Startup.cs"
      end

      controller_files.each do |file|
        analyze_controller_file(file, route_patterns)
      end
    end

    private def analyze_controller_file(file : String, route_patterns : Array(String))
      return unless File.exists?(file)

      content = File.read(file, encoding: "utf-8", invalid: :skip)
      return unless content.includes?("Controller")

      controller_name = extract_controller_name(content)
      return if controller_name.empty?

      controller_route = extract_controller_route(content)
      lines = content.lines

      http_method = "GET"
      action_route = ""
      in_class = false

      i = 0
      while i < lines.size
        line = lines[i]

        in_class = true if line.includes?("class") && line.includes?("Controller")
        if in_class
          http_method, action_route = update_http_context(line, http_method, action_route)
        end

        if in_class && potential_action_signature?(line)
          signature, end_index = build_signature(lines, i)
          if action_method?(signature)
            action_name = extract_action_name(signature)
            unless action_name.empty?
              parameters = extract_parameters(signature, http_method)
              effective_action_route = action_route
              if !controller_route.empty? && controller_route == effective_action_route
                effective_action_route = ""
              end
              routes = resolve_routes(controller_route, effective_action_route, controller_name, action_name, parameters, route_patterns)

              routes.each do |route|
                details = Details.new(PathInfo.new(file, i + 1))
                endpoint = Endpoint.new(route, http_method, details)

                align_params_with_route(parameters, route).each do |param|
                  endpoint.params << param
                end

                @result << endpoint
              end

              http_method = "GET"
              action_route = ""
            end
          end
          i = end_index
        end

        i += 1
      end
    end

    private def update_http_context(line : String, current_method : String, action_route : String) : Tuple(String, String)
      http_method = current_method
      route = action_route

      if line.includes?("[HttpPost")
        http_method = "POST"
        route = extract_attribute_route(line, "HttpPost", route)
      elsif line.includes?("[HttpGet")
        http_method = "GET"
        route = extract_attribute_route(line, "HttpGet", route)
      elsif line.includes?("[HttpPut")
        http_method = "PUT"
        route = extract_attribute_route(line, "HttpPut", route)
      elsif line.includes?("[HttpDelete")
        http_method = "DELETE"
        route = extract_attribute_route(line, "HttpDelete", route)
      elsif line.includes?("[HttpPatch")
        http_method = "PATCH"
        route = extract_attribute_route(line, "HttpPatch", route)
      elsif line.includes?("[HttpHead")
        http_method = "HEAD"
        route = extract_attribute_route(line, "HttpHead", route)
      elsif line.includes?("[HttpOptions")
        http_method = "OPTIONS"
        route = extract_attribute_route(line, "HttpOptions", route)
      elsif line.includes?("[Route")
        route = extract_attribute_route(line, "Route", route)
      end

      {http_method, route}
    end

    private def potential_action_signature?(line : String) : Bool
      line.includes?("public") && line.includes?("(") && !line.includes?(" class ")
    end

    private def build_signature(lines : Array(String), start_index : Int32) : Tuple(String, Int32)
      signature = lines[start_index]
      paren_count = signature.count('(') - signature.count(')')
      index = start_index + 1

      while paren_count > 0 && index < lines.size
        signature += " " + lines[index]
        paren_count += lines[index].count('(') - lines[index].count(')')
        index += 1
      end

      {signature, index - 1}
    end

    private def action_method?(signature : String) : Bool
      signature.includes?("ActionResult") ||
        signature.includes?("IActionResult") ||
        signature.includes?("JsonResult") ||
        signature.includes?("ViewResult")
    end

    private def extract_controller_name(content : String) : String
      match = content.match(/class\s+(\w+)Controller\s*:\s*[\w<>\s,]*Controller\w*/)
      return "" unless match
      match[1]
    end

    private def extract_action_name(signature : String) : String
      match = signature.match(/public\s+(?:async\s+)?(?:override\s+)?(?:virtual\s+)?[\w<>\[\],\s]+\s+(\w+)\s*\(/)
      return "" unless match
      match[1]
    end

    private def extract_parameters(signature : String, http_method : String) : Array(Param)
      parameters = [] of Param

      match = signature.match(/\((.*)\)/m)
      return parameters unless match

      param_list = match[1].strip
      return parameters if param_list.empty?

      default_param_type = default_param_type(http_method)

      param_list.split(',').each do |param_def|
        cleaned_def, param_type = normalize_param_definition(param_def)
        next if cleaned_def.empty?

        parts = cleaned_def.split(/\s+/)
        next if parts.empty?

        param_name = parts.last.gsub(/=.*$/, "").strip
        next if param_name.empty?

        parameters << Param.new(param_name, "", param_type || default_param_type)
      end

      parameters
    end

    private def default_param_type(http_method : String) : String
      case http_method
      when "POST", "PUT", "PATCH"
        "form"
      else
        "query"
      end
    end

    private def normalize_param_definition(param_def : String) : Tuple(String, String?)
      param_type = nil
      cleaned = param_def.strip

      {
        "FromQuery"  => "query",
        "FromRoute"  => "path",
        "FromBody"   => "json",
        "FromHeader" => "header",
        "FromForm"   => "form",
        "FromCookie" => "cookie",
      }.each do |attr, type|
        if cleaned.includes?("[#{attr}")
          param_type = type
          cleaned = cleaned.gsub(/\[#{attr}[^\]]*\]/, "")
        end
      end

      {cleaned.strip, param_type}
    end

    private def extract_controller_route(content : String) : String
      lines = content.lines
      lines.each_with_index do |line, index|
        if line =~ /class\s+\w+Controller/
          search_index = index - 1
          while search_index >= 0 && search_index >= index - 5
            candidate_line = lines[search_index]
            if candidate_line.includes?("[Route")
              route = extract_attribute_route(candidate_line, "Route", "")
              return route if route != ""
            end
            search_index -= 1
          end
          break
        end
      end
      ""
    end

    private def extract_attribute_route(line : String, attribute : String, current_route : String) : String
      # Try to extract the first string literal inside the attribute
      regex_with_value = Regex.new("\\[#{attribute}[^(]*\\(\\s*\"([^\"]+)\"")
      if (match = regex_with_value.match(line))
        return match[1]
      end

      template_regex = /Template\s*=\s*"([^"]+)"/
      if (match = template_regex.match(line))
        return match[1]
      end

      current_route
    end

    private def resolve_routes(controller_route : String, action_route : String, controller_name : String, action_name : String, parameters : Array(Param), route_patterns : Array(String)) : Array(String)
      routes = build_attribute_routes(controller_route, action_route, controller_name, action_name, parameters)

      if routes.empty?
        route_patterns.each do |pattern|
          raw_route = replace_tokens(pattern, controller_name, action_name)
          raw_route = prune_optional_placeholders(raw_route, parameters)
          routes << normalize_route(raw_route)
        end
      end

      routes.uniq
    end

    private def build_attribute_routes(controller_route : String, action_route : String, controller_name : String, action_name : String, parameters : Array(Param)) : Array(String)
      routes = [] of String
      has_controller_route = !controller_route.empty?
      has_action_route = !action_route.empty?

      return routes unless has_controller_route || has_action_route

      base_route = replace_tokens(controller_route, controller_name, action_name)
      action_part = replace_tokens(action_route, controller_name, action_name)

      if !has_action_route
        raw_route = prune_optional_placeholders(base_route, parameters)
        routes << normalize_route(raw_route) unless raw_route.empty?
      elsif action_part.starts_with?("/")
        raw_route = prune_optional_placeholders(action_part, parameters)
        routes << normalize_route(raw_route)
      else
        combined = [base_route, action_part].reject(&.empty?).join("/")
        raw_route = prune_optional_placeholders(combined, parameters)
        routes << normalize_route(raw_route)
      end

      routes
    end

    private def replace_tokens(route : String, controller_name : String, action_name : String) : String
      return "" if route.empty?

      normalized = route.strip
      normalized = normalized.gsub("[controller]", controller_name)
      normalized = normalized.gsub("{controller}", controller_name)
      normalized = normalized.gsub(/{controller=[^}]+}/, controller_name)
      normalized = normalized.gsub("[action]", action_name)
      normalized = normalized.gsub("{action}", action_name)
      normalized = normalized.gsub(/{action=[^}]+}/, action_name)

      normalized
    end

    private def normalize_route(route : String) : String
      normalized = route.strip
      normalized = normalized.gsub(/^\//, "").gsub(/\/+/, "/")
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = "/" if normalized == "//" || normalized == "/"
      normalized
    end

    private def build_endpoint_from_route(raw_route : String, http_method : String, file : String, line : Int32) : Endpoint?
      return nil if raw_route.empty?

      route = normalize_route(raw_route)
      params = build_path_params(route)
      route = prune_optional_placeholders(route, params)

      details = Details.new(PathInfo.new(file, line))
      endpoint = Endpoint.new(route, http_method, details)
      params.each { |param| endpoint.params << param }
      endpoint
    end

    private def build_path_params(route : String) : Array(Param)
      extract_route_placeholders(route).map do |name|
        Param.new(name, "", "path")
      end
    end

    private def prune_optional_placeholders(route : String, parameters : Array(Param)) : String
      param_names = parameters.map(&.name)
      result = route.dup

      placeholder_regex = /\{([^}]+)\}/
      route.scan(placeholder_regex) do |match|
        raw = match[1]? || match[0]
        next unless raw

        optional = raw.ends_with?("?")
        name = raw.split(":").first
        name = name.gsub(/\?$/, "")

        if optional && !param_names.includes?(name)
          result = result.gsub("/{#{raw}}", "")
          result = result.gsub("{#{raw}}/", "")
          result = result.gsub("{#{raw}}", "")
        elsif optional
          cleaned = raw.gsub("?", "")
          result = result.gsub("{#{raw}}", "{#{cleaned}}")
        end
      end

      result
    end

    private def align_params_with_route(params : Array(Param), route : String) : Array(Param)
      path_keys = extract_route_placeholders(route)

      params.map do |param|
        param_copy = Param.new(param.name, param.value, param.param_type)
        if path_keys.includes?(param.name)
          param_copy.param_type = "path"
        end
        param_copy
      end
    end

    private def extract_route_placeholders(route : String) : Array(String)
      keys = [] of String
      placeholder_regex = /\{([^}]+)\}/

      route.scan(placeholder_regex) do |match|
        raw = match[1]? || match[0]
        next unless raw
        cleaned = raw.split(":").first
        cleaned = cleaned.gsub(/\?$/, "")
        cleaned = cleaned.lstrip("*")
        keys << cleaned
      end

      keys.uniq
    end
  end
end
