require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class AspNetCoreMvc < Analyzer
    include Common

    DEFAULT_ROUTE = "{controller=Home}/{action=Index}/{id?}"

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      route_patterns = load_route_patterns
      analyze_controllers(route_patterns, include_callee)
      analyze_route_builder_endpoints(include_callee)
      @result
    end

    private def analyze_route_builder_endpoints(include_callee : Bool)
      map_regex = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*"([^"]+)"/m
      chained_group_map_regex = /MapGroup\s*\(\s*"([^"]+)"\s*\)\s*\.Map(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*"([^"]+)"/m
      map_methods_block_regex = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*\(\s*"([^"]+)"\s*,\s*([\s\S]+?)=>/m
      chained_group_map_methods_regex = /MapGroup\s*\(\s*"([^"]+)"\s*\)\s*\.MapMethods\s*\(\s*"([^"]+)"\s*,\s*([\s\S]+?)=>/m

      get_files_by_extension(".cs").each do |file|
        next unless File.exists?(file)
        next if Common.csharp_test_path?(file)

        content = read_file_content(file)
        group_prefixes = extract_map_group_prefixes(content)
        lines = content.lines
        lines.each_with_index do |line, index|
          if route_builder_line?(line)
            block = extract_map_block(lines, index)
            if chained_match = chained_group_map_regex.match(block)
              http_method = chained_match[2].upcase
              route = join_route_parts(chained_match[1], chained_match[3])
            elsif match = map_regex.match(block)
              receiver = match[1]?
              http_method = match[2].upcase
              route = apply_group_prefix(match[3], receiver, group_prefixes)
            else
              route = nil
              http_method = nil
            end

            next unless route && http_method

            extra_params = extract_params_from_block(block)
            extra_params.concat(extract_bind_params_from_file(block, lines))
            endpoint = build_endpoint_from_route(route, http_method, file, index + 1, extra_params)
            if endpoint
              attach_csharp_callees(endpoint, block, file, index + 1, include_callee)
              @result << endpoint
            end
          end

          if line.includes?("MapMethods")
            block = extract_map_block(lines, index)
            route = nil
            methods = [] of String

            if chained_match = chained_group_map_methods_regex.match(block)
              route = join_route_parts(chained_match[1], chained_match[2])
              methods_section = chained_match[3]
              methods = methods_section.scan(/"([A-Za-z]+)"/).map(&.[1]?.to_s.upcase).reject(&.empty?).uniq!
            elsif match = block.match(/(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*\(\s*"([^"]+)"\s*,\s*new[^{]*\{([^}]*)\}/m)
              receiver = match[1]?
              route = apply_group_prefix(match[2], receiver, group_prefixes)
              methods = match[3].split(",").map(&.gsub(/["\s]/, "").upcase).reject(&.empty?).uniq!
            elsif match = map_methods_block_regex.match(block)
              receiver = match[1]?
              route = apply_group_prefix(match[2], receiver, group_prefixes)
              methods_section = match[3]
              methods = methods_section.scan(/"([A-Za-z]+)"/).map(&.[1]?.to_s.upcase).reject(&.empty?).uniq!
            end

            if route && methods.size > 0
              extra_params = extract_params_from_block(block)
              extra_params.concat(extract_bind_params_from_file(block, lines))
              methods.each do |method|
                endpoint = build_endpoint_from_route(route, method, file, index + 1, extra_params)
                if endpoint
                  attach_csharp_callees(endpoint, block, file, index + 1, include_callee)
                  @result << endpoint
                end
              end
            end
          end
        end
      end
    end

    private def route_builder_line?(line : String) : Bool
      line.includes?("MapGet") ||
        line.includes?("MapPost") ||
        line.includes?("MapPut") ||
        line.includes?("MapDelete") ||
        line.includes?("MapPatch") ||
        line.includes?("MapHead") ||
        line.includes?("MapOptions")
    end

    private def extract_map_group_prefixes(content : String) : Hash(String, String)
      prefixes = Hash(String, String).new
      group_assignment_regex = /(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.MapGroup\s*\(\s*"([^"]+)"\s*\)/

      content.scan(group_assignment_regex) do |match|
        variable = match[1]
        parent = match[2]
        prefix = match[3]
        parent_prefix = prefixes[parent]? || ""
        prefixes[variable] = join_route_parts(parent_prefix, prefix)
      end

      prefixes
    end

    private def apply_group_prefix(route : String, receiver : String?, group_prefixes : Hash(String, String)) : String
      return route unless receiver
      prefix = group_prefixes[receiver]?
      return route unless prefix
      join_route_parts(prefix, route)
    end

    private def join_route_parts(*parts : String) : String
      clean_parts = parts.compact_map do |part|
        clean = part.strip.gsub(/^\//, "").gsub(/\/$/, "")
        clean.empty? ? nil : clean
      end
      return "/" if clean_parts.empty?
      "/" + clean_parts.join("/")
    end

    private def extract_map_block(lines : Array(String), start_index : Int32) : String
      io = String::Builder.new
      paren_depth = 0
      brace_depth = 0
      i = start_index

      while i < lines.size
        line = lines[i]
        paren_depth += line.count('(') - line.count(')')
        brace_depth += line.count('{') - line.count('}')
        io << line
        io << '\n'

        if paren_depth <= 0 && brace_depth <= 0 && line.includes?(";")
          break
        end

        i += 1
      end

      io.to_s
    end

    private def extract_params_from_block(block : String) : Array(Param)
      params = [] of Param
      query_regex = /Request\.Query\["([^"]+)"\]/
      header_regex = /Request\.Headers\["([^"]+)"\]/
      cookie_regex = /Request\.Cookies\["([^"]+)"\]/
      form_regex = /Request\.Form\["([^"]+)"\]/
      json_property_regex = /GetProperty\s*\(\s*"([^"]+)"\s*\)/

      block.scan(query_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "query") if key && !key.empty?
      end
      block.scan(header_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "header") if key && !key.empty?
      end
      block.scan(cookie_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "cookie") if key && !key.empty?
      end
      block.scan(form_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "form") if key && !key.empty?
      end
      block.scan(json_property_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "json") if key && !key.empty?
      end

      params.uniq(&.name)
    end

    private def extract_bind_params_from_file(block : String, lines : Array(String)) : Array(Param)
      return [] of Param unless block.includes?("Bind(")

      params = [] of Param
      lines.each_with_index do |line, index|
        next unless line.includes?("Bind(")
        next unless line.includes?("public") || line.includes?("private") || line.includes?("protected") || line.includes?("internal") || line.includes?("static")

        _, end_idx = build_signature(lines, index)
        body = extract_method_block(lines, end_idx)
        params.concat(extract_params_from_block(body))
      end

      if params.empty? && block =~ /parameters\.Url/
        params << Param.new("url", "", "query")
      end

      params.uniq(&.name)
    end

    private def load_route_patterns : Array(String)
      patterns = [] of String
      files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        base == "Program.cs" || base == "Startup.cs"
      end

      files.each do |file|
        begin
          content = read_file_content(file)
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

    private def analyze_controllers(route_patterns : Array(String), include_callee : Bool)
      controller_files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        next false if Common.csharp_test_path?(file)
        base.includes?("Controller") && !base.ends_with?("RouteConfig.cs") && base != "Program.cs" && base != "Startup.cs"
      end

      controller_files.each do |file|
        analyze_controller_file(file, route_patterns, include_callee)
      end
    end

    private def analyze_controller_file(file : String, route_patterns : Array(String), include_callee : Bool)
      return unless File.exists?(file)

      content = read_file_content(file)
      return unless content.includes?("Controller")

      controller_name = extract_controller_name(content)
      return if controller_name.empty?

      controller_route = extract_controller_route(content)
      lines = content.lines

      http_method = "GET"
      action_route = ""
      explicit_endpoint_attribute = false
      non_action_attribute = false
      in_class = false

      i = 0
      while i < lines.size
        line = lines[i]

        in_class = true if line.includes?("class") && line.includes?("Controller")
        if in_class
          http_method, action_route, found_attribute = update_http_context(line, http_method, action_route)
          explicit_endpoint_attribute ||= found_attribute
          non_action_attribute = true if line.includes?("[NonAction")
        end

        if in_class && potential_action_signature?(line)
          signature, end_index = build_signature(lines, i)
          if !non_action_attribute && action_method?(signature, explicit_endpoint_attribute)
            action_name = extract_action_name(signature)
            unless action_name.empty?
              parameters = extract_parameters(signature, http_method)
              body_block = extract_method_block(lines, end_index)
              body_params = extract_params_from_block(body_block)
              parameters = merge_params(parameters, body_params, http_method)
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

                attach_csharp_callees(endpoint, body_block, file, end_index + 1, include_callee, skip_first_line: true)
                @result << endpoint
              end

              http_method = "GET"
              action_route = ""
              explicit_endpoint_attribute = false
              non_action_attribute = false
            end
          end
          if non_action_attribute
            http_method = "GET"
            action_route = ""
            explicit_endpoint_attribute = false
          end
          non_action_attribute = false
          i = end_index
        end

        i += 1
      end
    end

    private def update_http_context(line : String, current_method : String, action_route : String) : Tuple(String, String, Bool)
      http_method = current_method
      route = action_route
      found_attribute = false

      if line.includes?("[HttpPost")
        http_method = "POST"
        route = extract_attribute_route(line, "HttpPost", route)
        found_attribute = true
      elsif line.includes?("[HttpGet")
        http_method = "GET"
        route = extract_attribute_route(line, "HttpGet", route)
        found_attribute = true
      elsif line.includes?("[HttpPut")
        http_method = "PUT"
        route = extract_attribute_route(line, "HttpPut", route)
        found_attribute = true
      elsif line.includes?("[HttpDelete")
        http_method = "DELETE"
        route = extract_attribute_route(line, "HttpDelete", route)
        found_attribute = true
      elsif line.includes?("[HttpPatch")
        http_method = "PATCH"
        route = extract_attribute_route(line, "HttpPatch", route)
        found_attribute = true
      elsif line.includes?("[HttpHead")
        http_method = "HEAD"
        route = extract_attribute_route(line, "HttpHead", route)
        found_attribute = true
      elsif line.includes?("[HttpOptions")
        http_method = "OPTIONS"
        route = extract_attribute_route(line, "HttpOptions", route)
        found_attribute = true
      elsif line.includes?("[Route")
        route = extract_attribute_route(line, "Route", route)
        found_attribute = true
      end

      {http_method, route, found_attribute}
    end

    private def potential_action_signature?(line : String) : Bool
      line.includes?("public") && line.includes?("(") && !line.includes?(" class ")
    end

    private def action_method?(signature : String, explicit_endpoint_attribute : Bool) : Bool
      return true if explicit_endpoint_attribute

      signature.includes?("ActionResult") ||
        signature.includes?("IActionResult") ||
        signature.includes?("JsonResult") ||
        signature.includes?("ViewResult") ||
        signature.includes?("IResult") ||
        signature.matches?(/Task\s*<\s*(?:IEnumerable|List|PagedResult|Result|Response|[A-Z]\w*)/)
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

      split_csharp_parameters(param_list).each do |param_def|
        cleaned_def, param_type = normalize_param_definition(param_def)
        next if cleaned_def.empty?
        next if param_type == "service"

        if match = cleaned_def.match(/(\w+)\s*(?:=\s*[^,]+)?\s*$/)
          param_name = match[1]
          parameters << Param.new(param_name, "", param_type || default_param_type)
        end
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
        "FromQuery"         => "query",
        "FromRoute"         => "path",
        "FromBody"          => "json",
        "FromHeader"        => "header",
        "FromForm"          => "form",
        "FromCookie"        => "cookie",
        "FromServices"      => "service",
        "FromKeyedServices" => "service",
      }.each do |attr, type|
        if cleaned.includes?("[#{attr}")
          param_type = type
          cleaned = cleaned.gsub(/\[#{attr}[^\]]*\]/, "")
        end
      end

      {cleaned.strip, param_type}
    end

    private def merge_params(signature_params : Array(Param), body_params : Array(Param), http_method : String) : Array(Param)
      merged = signature_params.map { |p| Param.new(p.name, p.value, p.param_type) }
      default_type = default_param_type(http_method)

      body_params.each do |extra|
        if idx = merged.index { |p| p.name == extra.name }
          existing = merged[idx]
          if existing.param_type == default_type || existing.param_type == "query" || existing.param_type == "form"
            merged[idx] = extra
          end
        else
          merged << extra
        end
      end

      merged
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

    private ATTRIBUTE_REGEXES = {
      "HttpPost"    => /\[HttpPost[^(]*+\(\s*"([^"]+)"/,
      "HttpGet"     => /\[HttpGet[^(]*+\(\s*"([^"]+)"/,
      "HttpPut"     => /\[HttpPut[^(]*+\(\s*"([^"]+)"/,
      "HttpDelete"  => /\[HttpDelete[^(]*+\(\s*"([^"]+)"/,
      "HttpPatch"   => /\[HttpPatch[^(]*+\(\s*"([^"]+)"/,
      "HttpHead"    => /\[HttpHead[^(]*+\(\s*"([^"]+)"/,
      "HttpOptions" => /\[HttpOptions[^(]*+\(\s*"([^"]+)"/,
      "Route"       => /\[Route[^(]*+\(\s*"([^"]+)"/,
    }

    private TEMPLATE_REGEX = /Template\s*=\s*"([^"]+)"/

    private def extract_attribute_route(line : String, attribute : String, current_route : String) : String
      # Try to extract the first string literal inside the attribute
      regex_with_value = ATTRIBUTE_REGEXES[attribute]? || Regex.new("\\[#{attribute}[^(]*+\\(\\s*\"([^\"]+)\"")

      if match = regex_with_value.match(line)
        return match[1]
      end

      if match = TEMPLATE_REGEX.match(line)
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

    private def build_endpoint_from_route(raw_route : String, http_method : String, file : String, line : Int32, extra_params : Array(Param) = [] of Param) : Endpoint?
      return if raw_route.empty?

      route = normalize_route(raw_route)
      params = build_path_params(route)
      extra_params.each do |param|
        params << param unless params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      end
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

      mapped = params.map do |param|
        param_copy = Param.new(param.name, param.value, param.param_type)
        if path_keys.includes?(param.name)
          param_copy.param_type = "path"
        end
        param_copy
      end

      path_keys.each do |key|
        unless mapped.any? { |param| param.name == key }
          mapped << Param.new(key, "", "path")
        end
      end

      mapped
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
