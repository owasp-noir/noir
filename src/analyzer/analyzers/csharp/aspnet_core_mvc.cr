require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class AspNetCoreMvc < Analyzer
    include Common

    DEFAULT_ROUTE = "{controller=Home}/{action=Index}/{id?}"

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The `[FromX]` attribute set is fixed, so
    # precompile its markers and strippers once at load time; the
    # param-name regex interpolates a discovered name and is memoized.
    FROM_ATTRIBUTE_PATTERNS = {
      "FromQuery"         => "query",
      "FromRoute"         => "path",
      "FromBody"          => "json",
      "FromHeader"        => "header",
      "FromForm"          => "form",
      "FromCookie"        => "cookie",
      "FromServices"      => "service",
      "FromKeyedServices" => "service",
    }.map do |attr, type|
      {"[#{attr}", /\[#{attr}[^\]]*\]/, type}
    end
    @param_name_strip_regexes = Hash(String, Regex).new

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      route_patterns_by_base = load_route_patterns_by_base
      analyze_controllers(route_patterns_by_base, include_callee)
      @result
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
      masked_lines = Noir::CSharpLexer.new(lines.join('\n')).masked_lines
      lines.each_with_index do |line, index|
        next unless line.includes?("Bind(")
        next unless line.includes?("public") || line.includes?("private") || line.includes?("protected") || line.includes?("internal") || line.includes?("static")

        _, end_idx = build_signature(lines, masked_lines, index)
        body = extract_method_block(lines, masked_lines, end_idx)
        params.concat(extract_params_from_block(body))
      end

      if params.empty? && block =~ /parameters\.Url/
        params << Param.new("url", "", "query")
      end

      params.uniq(&.name)
    end

    private def load_route_patterns_by_base : Hash(String, Array(String))
      patterns_by_base = Hash(String, Array(String)).new do |hash, key|
        hash[key] = [] of String
      end
      files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        base == "Program.cs" || base == "Startup.cs"
      end

      files.each do |file|
        begin
          content = read_file_content(file)
          patterns_by_base[configured_base_for(file)].concat(extract_route_patterns(content))
        rescue e
          logger.debug "Failed to read #{file}: #{e.message}"
        end
      end

      @base_paths.each do |base_path|
        patterns_by_base[base_path] << DEFAULT_ROUTE if patterns_by_base[base_path].empty?
      end

      patterns_by_base.each do |base_path, patterns|
        patterns << DEFAULT_ROUTE if patterns.empty?
        patterns_by_base[base_path] = patterns.uniq
      end

      patterns_by_base
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

    private def analyze_controllers(route_patterns_by_base : Hash(String, Array(String)), include_callee : Bool)
      controller_files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        next false if Common.csharp_test_path?(file)
        base.includes?("Controller") && !base.ends_with?("RouteConfig.cs") && base != "Program.cs" && base != "Startup.cs"
      end

      controller_files.each do |file|
        route_patterns = route_patterns_by_base[configured_base_for(file)]? || [DEFAULT_ROUTE]
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
      masked_lines = Noir::CSharpLexer.new(content).masked_lines

      # Accumulate every `[Http<Verb>(...)]` on the pending action so a method
      # carrying more than one (`[HttpGet(...)]` + `[HttpHead(...)]` for image/
      # file serving, GET+POST, …) emits an endpoint per verb instead of only
      # the last attribute. `route_attr` holds a verb-less `[Route(...)]` base
      # that a bare `[HttpGet]` (no path of its own) inherits.
      verb_routes = [] of Tuple(String, String)
      route_attr = ""
      explicit_endpoint_attribute = false
      non_action_attribute = false
      in_class = false

      i = 0
      while i < lines.size
        line = lines[i]

        in_class = true if line.includes?("class") && line.includes?("Controller")
        if in_class
          # Stitch together a multi-line `[Http<Verb>(\n   "/path",\n
          # Order = 1\n)]` attribute before running the
          # single-line matcher. The `[Http*]` opener arrives without
          # a closing paren on the same line, the path literal lives
          # on a subsequent line; the per-line matcher only
          # saw `[HttpPost(` and recorded POST with an empty path.
          attr_line, advance = stitch_multiline_attribute(lines, i)
          line = attr_line if advance > 0

          verb, verb_route, route_attr, found_attribute = collect_verb_route(line, route_attr)
          explicit_endpoint_attribute ||= found_attribute
          verb_routes << {verb, verb_route} if verb
          non_action_attribute = true if line.includes?("[NonAction")

          # Skip the continuation lines we just consumed; they're
          # already folded into `line`.
          i += advance if advance > 0
        end

        if in_class && potential_action_signature?(line)
          signature, end_index = build_signature(lines, masked_lines, i)
          if !non_action_attribute && action_method?(signature, explicit_endpoint_attribute)
            action_name = extract_action_name(signature)
            unless action_name.empty?
              body_block, body_line, skip_first = extract_callable_body(lines, masked_lines, end_index)
              body_params = extract_params_from_block(body_block)

              # No `[Http*]` attribute → convention-based (verb GET, route from
              # any `[Route]` base or the controller convention).
              emit_pairs = verb_routes.empty? ? [{"GET", route_attr}] : verb_routes
              emit_pairs.each do |emit_verb, emit_route|
                # A bare `[HttpGet]` whose `[Route("x")]` base arrived on a
                # later line collected an empty route — fall back to the base
                # so verb-then-`[Route]` ordering matches `[Route]`-then-verb.
                emit_route = route_attr if emit_route.empty? && !route_attr.empty?
                parameters = extract_parameters(signature, emit_verb)
                parameters = merge_params(parameters, body_params, emit_verb)
                effective_action_route = emit_route
                if !controller_route.empty? && controller_route == effective_action_route
                  effective_action_route = ""
                end
                routes = resolve_routes(controller_route, effective_action_route, controller_name, action_name, parameters, route_patterns)

                routes.each do |route|
                  details = Details.new(PathInfo.new(file, i + 1))
                  endpoint = Endpoint.new(route, emit_verb, details)

                  align_params_with_route(parameters, route).each do |param|
                    endpoint.params << param
                  end

                  attach_csharp_callees(endpoint, body_block, file, body_line + 1, include_callee, skip_first_line: skip_first)
                  @result << endpoint
                end
              end

              verb_routes = [] of Tuple(String, String)
              route_attr = ""
              explicit_endpoint_attribute = false
              non_action_attribute = false
            end
          end
          if non_action_attribute
            verb_routes = [] of Tuple(String, String)
            route_attr = ""
            explicit_endpoint_attribute = false
          end
          non_action_attribute = false
          i = end_index
        end

        i += 1
      end
    end

    # Collapses a `[Http<Verb>(...)` / `[Route(...)]` attribute that
    # was split across multiple lines into a single logical line so
    # the single-line attribute regexes in `extract_attribute_route`
    # can find the path literal. Returns `{joined_line, advance}`
    # where `advance` is the number of *extra* lines consumed; the
    # caller adds that to its loop index. A non-multi-line case
    # returns `{line, 0}` so the existing fast path is preserved.
    private def stitch_multiline_attribute(lines : Array(String), start : Int32) : Tuple(String, Int32)
      line = lines[start]
      return {line, 0} unless line =~ /\[(Http(Post|Get|Put|Delete|Patch|Head|Options)|Route)\b/

      # The attribute closes when paren+bracket depth returns to
      # zero. If the opening line is already balanced (paren and
      # bracket both close on the same line), no stitching needed.
      paren = line.count('(') - line.count(')')
      bracket = line.count('[') - line.count(']')
      return {line, 0} if paren <= 0 && bracket <= 0

      joined = line.rstrip
      idx = start + 1
      # Cap the read-ahead at 8 lines — far beyond what a real-world
      # attribute spans, but tight enough that a runaway file with
      # unbalanced brackets can't blow up the scan.
      max_read = (start + 8).clamp(0, lines.size - 1)
      while idx <= max_read
        nxt = lines[idx]
        joined += " " + nxt.strip
        paren += nxt.count('(') - nxt.count(')')
        bracket += nxt.count('[') - nxt.count(']')
        break if paren <= 0 && bracket <= 0
        idx += 1
      end

      {joined, idx - start}
    end

    # Attribute name carrying each verb, for `extract_attribute_route`.
    VERB_ATTRIBUTES = {
      "[HttpPost"    => {"POST", "HttpPost"},
      "[HttpGet"     => {"GET", "HttpGet"},
      "[HttpPut"     => {"PUT", "HttpPut"},
      "[HttpDelete"  => {"DELETE", "HttpDelete"},
      "[HttpPatch"   => {"PATCH", "HttpPatch"},
      "[HttpHead"    => {"HEAD", "HttpHead"},
      "[HttpOptions" => {"OPTIONS", "HttpOptions"},
    }

    # Classify one attribute line. Returns `{verb, verb_route, route_attr, found}`:
    # for an `[Http<Verb>(...)]` the verb + its route (falling back to the
    # `[Route]` base for a path-less attribute), with `route_attr` left
    # unchanged; for a verb-less `[Route("x")]` the new base in `route_attr`
    # (verb `nil`); for any other line, no change and `found = false`. Keeping
    # the verb separate lets the caller accumulate several verbs on one method.
    private def collect_verb_route(line : String, route_attr : String) : Tuple(String?, String, String, Bool)
      VERB_ATTRIBUTES.each do |marker, pair|
        next unless line.includes?(marker)
        verb, attr = pair
        return {verb, extract_attribute_route(line, attr, route_attr), route_attr, true}
      end

      if line.includes?("[Route")
        return {nil, route_attr, extract_attribute_route(line, "Route", route_attr), true}
      end

      {nil, route_attr, route_attr, false}
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
      # Any class whose name ends in `Controller` is a controller in ASP.NET
      # Core, regardless of its base list — so we no longer require a
      # `: Controller`/`: ControllerBase` suffix. This covers:
      #   * POCO controllers with no base class (`class UsersController { }`),
      #   * custom base classes (`: BaseApiController`),
      #   * C# 12 primary constructors (`class ArticlesController(IMediator m)`),
      #   * generic controllers (`class CrudController<T>`).
      # The enclosing file is already filtered to `*Controller.cs`, so the
      # match is unambiguous. `\b` after `Controller` avoids matching
      # `FooControllerOptions`-style helper types.
      match = content.match(/\bclass\s+(\w+)Controller\b/)
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

      param_list = extract_balanced_param_list(signature)
      return parameters unless param_list

      param_list = param_list.strip
      return parameters if param_list.empty?

      default_param_type = default_param_type(http_method)

      split_csharp_parameters(param_list).each do |param_def|
        cleaned_def, param_type = normalize_param_definition(param_def)
        next if cleaned_def.empty?
        next if param_type == "service"

        if match = cleaned_def.match(/(\w+)\s*(?:=\s*[^,]+)?\s*$/)
          param_name = match[1]

          # A complex/interface action parameter with no explicit `[FromX]`
          # attribute that names a DI service (an injected repository, the
          # DbContext, a MediatR sender, …) is not request input — model
          # binding never produces one. Dropping it removes a recurring FP.
          if param_type.nil?
            strip_regex = @param_name_strip_regexes[param_name] ||= /\b#{Regex.escape(param_name)}\b\s*(?:=\s*[^,]+)?\s*$/
            type_token = cleaned_def.sub(strip_regex, "").strip.split(/\s+/).last?
            next if type_token && Common.csharp_service_type?(type_token)
          end

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

      FROM_ATTRIBUTE_PATTERNS.each do |marker, attr_regex, type|
        if cleaned.includes?(marker)
          param_type = type
          cleaned = cleaned.gsub(attr_regex, "")
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
              return route unless route.empty?
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
