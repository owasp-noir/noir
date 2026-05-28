module Analyzer::CSharp::MinimalApiSupport
  MAP_METHODS = %w[Get Post Put Delete Patch Head Options]

  SIMPLE_BINDING_TYPES = Set{
    "bool", "byte", "sbyte", "short", "ushort", "int", "uint", "long", "ulong",
    "float", "double", "decimal", "char", "string", "Guid", "DateTime",
    "DateTimeOffset", "TimeSpan",
  }

  SERVICE_BINDING_TYPES = Set{
    "CancellationToken", "HttpContext", "HttpRequest", "HttpResponse", "ClaimsPrincipal",
    "IServiceProvider", "ILogger", "ILoggerFactory", "LinkGenerator",
  }

  private def analyze_minimal_api_files(include_callee : Bool)
    get_files_by_extension(".cs").each do |file|
      next unless File.exists?(file)
      next if Common.csharp_test_path?(file)

      content = read_file_content(file)
      next if content.includes?("ICarterModule")
      next unless minimal_api_source?(content)

      analyze_minimal_api_content(file, content, include_callee)
    end
  end

  private def minimal_api_source?(content : String) : Bool
    content.matches?(/\.\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods)\s*\(/) ||
      (content.matches?(/\.\s*Map\s*\(/) && minimal_api_context?(content))
  end

  private def minimal_api_context?(content : String) : Bool
    content.includes?("WebApplication") ||
      content.includes?("IEndpointRouteBuilder") ||
      content.includes?("RouteGroupBuilder")
  end

  private def analyze_minimal_api_content(file : String, content : String, include_callee : Bool)
    group_prefixes = extract_map_group_prefixes(content)
    lines = content.lines

    lines.each_with_index do |line, index|
      next unless route_builder_line?(line)

      block = extract_map_block(lines, index)
      extract_endpoints_from_map_block(block, group_prefixes, file, index + 1, lines, include_callee).each do |endpoint|
        @result << endpoint
      end
    end
  end

  private def route_builder_line?(line : String) : Bool
    MAP_METHODS.any? { |verb| line.includes?("Map#{verb}") } ||
      line.includes?("MapMethods") ||
      line.matches?(/\.\s*Map\s*\(/)
  end

  private def extract_endpoints_from_map_block(block : String,
                                               group_prefixes : Hash(String, String),
                                               file : String,
                                               line : Int32,
                                               file_lines : Array(String),
                                               include_callee : Bool) : Array(Endpoint)
    route, methods = extract_route_and_methods(block, group_prefixes)
    return [] of Endpoint unless route && methods.size > 0

    extra_params = extract_params_from_block(block)
    extra_params.concat(extract_bind_params_from_file(block, file_lines))
    extra_params.concat(extract_delegate_params(block, route, methods.first))

    endpoints = [] of Endpoint
    methods.each do |method|
      endpoint = build_endpoint_from_route(route, method, file, line, extra_params)
      next unless endpoint

      attach_csharp_callees(endpoint, block, file, line, include_callee)
      endpoints << endpoint
    end
    endpoints
  end

  private def extract_route_and_methods(block : String, group_prefixes : Hash(String, String)) : Tuple(String?, Array(String))
    if block.includes?("MapMethods")
      route, methods = extract_map_methods_route(block, group_prefixes)
      return {route, methods}
    end

    inline_prefix = extract_inline_group_prefix(block)
    if match = block.match(/(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]+)"/m)
      receiver = match[1]?
      route = apply_group_prefix(match[3], receiver, group_prefixes)
      route = join_route_parts(inline_prefix, route) unless inline_prefix.empty?
      return {route, [match[2].upcase]}
    end

    if match = block.match(/(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map\s*\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]+)"/m)
      receiver = match[1]?
      route = apply_group_prefix(match[2], receiver, group_prefixes)
      route = join_route_parts(inline_prefix, route) unless inline_prefix.empty?
      return {route, ["ANY"]}
    end

    {nil, [] of String}
  end

  private def extract_map_methods_route(block : String, group_prefixes : Hash(String, String)) : Tuple(String?, Array(String))
    inline_prefix = extract_inline_group_prefix(block)

    if match = block.match(/(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]+)"\s*,\s*([\s\S]+?)(?:=>|\);)/m)
      receiver = match[1]?
      route = apply_group_prefix(match[2], receiver, group_prefixes)
      route = join_route_parts(inline_prefix, route) unless inline_prefix.empty?
      methods = extract_http_methods(match[3])
      return {route, methods}
    end

    {nil, [] of String}
  end

  private def extract_http_methods(section : String) : Array(String)
    methods = section.scan(/"([A-Za-z]+)"/).map(&.[1]?.to_s.upcase).reject(&.empty?)

    section.scan(/HttpMethods\.([A-Za-z]+)/) do |match|
      method = match[1]?.to_s.upcase
      methods << method unless method.empty?
    end

    methods.uniq
  end

  private def extract_inline_group_prefix(block : String) : String
    map_index = block.index(/\.?\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods)?\s*\(/)
    return "" unless map_index

    prefix_source = block[0...map_index]
    parts = prefix_source.scan(/MapGroup\s*\(\s*@?"([^"]+)"/).map(&.[1]?.to_s)
    return "" if parts.empty?
    join_route_parts_array(parts)
  end

  private def extract_map_group_prefixes(content : String) : Hash(String, String)
    prefixes = Hash(String, String).new
    content.split(';').each do |statement|
      next unless statement.includes?("=") && statement.includes?("MapGroup")

      left, right = statement.split("=", 2)
      variable = left.strip.split(/\s+/).last?
      next unless variable && variable.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)

      parent_prefix = ""
      if parent_match = right.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*MapGroup\s*\(/)
        parent_prefix = prefixes[parent_match[1]]? || ""
      end

      parts = right.scan(/MapGroup\s*\(\s*@?"([^"]+)"/).map(&.[1]?.to_s)
      next if parts.empty?

      prefixes[variable] = join_route_parts_array([parent_prefix] + parts)
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
    join_route_parts_array(parts.to_a)
  end

  private def join_route_parts_array(parts : Array(String)) : String
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
    {
      /Request\.Query\["([^"]+)"\]/       => "query",
      /Request\.Headers\["([^"]+)"\]/     => "header",
      /Request\.Cookies\["([^"]+)"\]/     => "cookie",
      /Request\.Form\["([^"]+)"\]/        => "form",
      /GetProperty\s*\(\s*"([^"]+)"\s*\)/ => "json",
    }.each do |regex, param_type|
      block.scan(regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", param_type) if key && !key.empty?
      end
    end

    params.uniq(&.name)
  end

  private def extract_bind_params_from_file(block : String, lines : Array(String)) : Array(Param)
    return [] of Param unless block.includes?("Bind(") || block.includes?("BindAsync(")

    params = [] of Param
    lines.each_with_index do |line, index|
      next unless line.includes?("Bind(") || line.includes?("BindAsync(")
      next unless line.includes?("public") || line.includes?("private") || line.includes?("protected") || line.includes?("internal") || line.includes?("static")

      _, end_idx = build_signature(lines, index)
      body = extract_method_block(lines, end_idx)
      params.concat(extract_params_from_block(body))
    end

    params.uniq(&.name)
  end

  private def extract_delegate_params(block : String, route : String, http_method : String) : Array(Param)
    lambda_params = extract_lambda_param_list(block)
    return [] of Param if lambda_params.empty?

    route_params = extract_route_placeholders(route)
    split_csharp_parameters(lambda_params).compact_map do |param_def|
      delegate_param_to_noir_param(param_def, route_params, http_method)
    end.uniq!(&.name)
  end

  private def extract_lambda_param_list(block : String) : String
    arrow_index = block.index("=>")
    return "" unless arrow_index

    end_index = arrow_index - 1
    while end_index >= 0 && block[end_index].ascii_whitespace?
      end_index -= 1
    end
    return "" if end_index < 0

    if block[end_index] == ')'
      depth = 0
      index = end_index
      while index >= 0
        case block[index]
        when ')'
          depth += 1
        when '('
          depth -= 1
          return block[(index + 1)...end_index] if depth == 0
        end
        index -= 1
      end

      return ""
    end

    start_index = end_index
    while start_index >= 0 && (block[start_index].ascii_alphanumeric? || block[start_index] == '_')
      start_index -= 1
    end
    block[(start_index + 1)..end_index]
  end

  private def delegate_param_to_noir_param(param_def : String, route_params : Array(String), http_method : String) : Param?
    cleaned = param_def.strip
    return if cleaned.empty?

    explicit_name = extract_explicit_binding_name(cleaned)
    param_type = binding_attribute_type(cleaned)
    cleaned = cleaned.gsub(/\[[^\]]+\]\s*/, "").strip
    cleaned = cleaned.sub(/=.*/, "").strip
    cleaned = cleaned.gsub(/\b(ref|out|in|params)\b/, "").strip
    return if cleaned.empty?

    name_match = cleaned.match(/([A-Za-z_][A-Za-z0-9_]*)\s*$/)
    return unless name_match

    name = explicit_name || name_match[1]
    type_name = cleaned[0...(cleaned.size - name_match[1].size)].strip
      .gsub(/\?$/, "")
      .split(/\s+/).last? || ""
    type_name = type_name.split(".").last

    return if service_binding?(type_name, cleaned, param_type)

    if route_params.includes?(name)
      param_type = "path"
    elsif param_type.nil?
      param_type = default_delegate_param_type(type_name, http_method)
    end

    return if param_type == "service"
    Param.new(name, "", param_type || "query")
  end

  private def extract_explicit_binding_name(param_def : String) : String?
    if match = param_def.match(/\[From(?:Query|Route|Body|Header|Form)\s*\([^\]]*(?:Name\s*=\s*)?"([^"]+)"/)
      return match[1]
    end

    nil
  end

  private def binding_attribute_type(param_def : String) : String?
    {
      "FromQuery"         => "query",
      "FromRoute"         => "path",
      "FromBody"          => "json",
      "FromHeader"        => "header",
      "FromForm"          => "form",
      "FromServices"      => "service",
      "FromKeyedServices" => "service",
    }.each do |attr, param_type|
      return param_type if param_def.includes?("[#{attr}")
    end

    nil
  end

  private def service_binding?(type_name : String, full_definition : String, param_type : String?) : Bool
    return true if param_type == "service"
    return true if SERVICE_BINDING_TYPES.includes?(type_name)
    return true if full_definition.includes?("HttpContext") || full_definition.includes?("HttpRequest") || full_definition.includes?("HttpResponse")
    type_name.starts_with?("ILogger")
  end

  private def default_delegate_param_type(type_name : String, http_method : String) : String
    return "query" if SIMPLE_BINDING_TYPES.includes?(type_name)

    case http_method
    when "POST", "PUT", "PATCH"
      "json"
    else
      "query"
    end
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

  private def normalize_route(route : String) : String
    normalized = route.strip
    normalized = normalized.gsub(/^\//, "").gsub(/\/+/, "/")
    normalized = "/" + normalized unless normalized.starts_with?("/")
    normalized = "/" if normalized == "//" || normalized == "/"
    normalized
  end

  private def build_path_params(route : String) : Array(Param)
    extract_route_placeholders(route).map do |name|
      Param.new(name, "", "path")
    end
  end

  private def prune_optional_placeholders(route : String, parameters : Array(Param)) : String
    param_names = parameters.map(&.name)
    result = route.dup

    route.scan(/\{([^}]+)\}/) do |match|
      raw = match[1]? || match[0]
      next unless raw

      optional = raw.ends_with?("?")
      name = raw.split(":").first.gsub(/\?$/, "")

      if optional && !param_names.includes?(name)
        result = result.gsub("/{#{raw}}", "")
        result = result.gsub("{#{raw}}/", "")
        result = result.gsub("{#{raw}}", "")
      elsif optional
        result = result.gsub("{#{raw}}", "{#{raw.gsub("?", "")}}")
      end
    end

    result
  end

  private def extract_route_placeholders(route : String) : Array(String)
    keys = [] of String
    route.scan(/\{([^}]+)\}/) do |match|
      raw = match[1]? || match[0]
      next unless raw

      cleaned = raw.split(":").first.gsub(/\?$/, "").lstrip("*")
      keys << cleaned
    end

    keys.uniq
  end
end
