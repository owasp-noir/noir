require "json"
require "uri"
require "../utils/http_symbols"

module OutputBuilderOasCommon
  VALID_OPERATION_METHODS = Set{"get", "put", "post", "delete", "options", "head", "patch", "trace"}
  ANY_OPERATION_METHODS   = WILDCARD_HTTP_METHODS.map(&.downcase)

  private def normalize_oas_path(raw_url : String) : String
    uri = URI.parse(raw_url)
    path = uri.path
    path = "/" if path.empty?

    # Express-style optional segments (`/:id{/:op}`) are not representable as
    # optional in OpenAPI path templates. Drop the route-syntax braces so the
    # emitted path remains a valid template instead of `/users/{id}{/{op}}`.
    path = path.gsub(/\{\/:(\w+)\}/, "/:\\1")
    path = path.gsub(/\{\/([^{}]+)\}/, "/\\1")

    # Convert typed placeholders before the generic :param pass; otherwise
    # `<int:id>` becomes `<int{id}>` and can no longer be normalized.
    path = path.gsub(/<[^:>]+:(\w+)>/, "{\\1}")
    path = path.gsub(/<(\w+)>/, "{\\1}")
    path = path.gsub(/\*(\w+)/, "{\\1}")
    path = path.gsub(/:(\w+)/, "{\\1}")

    path.starts_with?("/") ? path : "/#{path}"
  end

  private def path_template_names(path : String) : Array(String)
    names = path.scan(/\{([^{}\/]+)\}/).map { |match| match[1] }
    names.uniq!
    names
  end

  private def operation_methods(method : String) : Array(String)
    normalized = method.downcase
    return [normalized] if VALID_OPERATION_METHODS.includes?(normalized)
    return ANY_OPERATION_METHODS if {"any", "all", "forward", "use"}.includes?(normalized)

    [] of String
  end

  private def add_unsupported_method_extension(path_item : Hash(String, JSON::Any), method : String)
    methods = [] of String
    if existing = path_item["x-noir-unsupported-methods"]?
      methods = existing.as_a.map(&.as_s)
    end

    methods << method unless methods.includes?(method)
    path_item["x-noir-unsupported-methods"] = JSON::Any.new(methods.map { |m| JSON::Any.new(m) })
  end

  private def parameter_key(parameter : Hash(String, JSON::Any)) : String
    "#{parameter["in"].as_s}\0#{parameter["name"].as_s}"
  end

  private def append_unique_parameter(parameters : Array(Hash(String, JSON::Any)), parameter : Hash(String, JSON::Any))
    key = parameter_key(parameter)
    return if parameters.any? { |existing| parameter_key(existing) == key }

    parameters << parameter
  end

  private def merge_parameters(existing : Array(JSON::Any), incoming : Array(JSON::Any)) : Array(JSON::Any)
    merged = [] of Hash(String, JSON::Any)

    (existing + incoming).each do |parameter|
      append_unique_parameter(merged, parameter.as_h)
    end

    merged.map { |parameter| JSON::Any.new(parameter) }
  end

  private def merge_request_body(existing : JSON::Any?, incoming : JSON::Any?) : JSON::Any?
    return incoming unless existing
    return existing unless incoming

    existing_hash = existing.as_h.dup
    incoming_hash = incoming.as_h

    if existing_content = existing_hash["content"]?
      if incoming_content = incoming_hash["content"]?
        content = existing_content.as_h.dup
        incoming_content.as_h.each do |media_type, media_value|
          content[media_type] = media_value unless content.has_key?(media_type)
        end
        existing_hash["content"] = JSON::Any.new(content)
      end
    elsif incoming_content = incoming_hash["content"]?
      existing_hash["content"] = incoming_content
    end

    JSON::Any.new(existing_hash)
  end

  private def merge_operations(existing : JSON::Any, incoming : Hash(String, JSON::Any)) : JSON::Any
    merged = existing.as_h.dup

    if existing_parameters = merged["parameters"]?
      incoming_parameters = incoming["parameters"]?.try(&.as_a) || [] of JSON::Any
      merged["parameters"] = JSON::Any.new(merge_parameters(existing_parameters.as_a, incoming_parameters))
    elsif incoming_parameters = incoming["parameters"]?
      merged["parameters"] = incoming_parameters
    end

    if request_body = merge_request_body(merged["requestBody"]?, incoming["requestBody"]?)
      merged["requestBody"] = request_body
    end

    incoming.each do |key, value|
      next if {"parameters", "requestBody"}.includes?(key)
      merged[key] = value unless merged.has_key?(key)
    end

    JSON::Any.new(merged)
  end

  private def add_operation(path_item : Hash(String, JSON::Any), method : String, operation : Hash(String, JSON::Any))
    if existing = path_item[method]?
      path_item[method] = merge_operations(existing, operation)
    else
      path_item[method] = JSON::Any.new(operation)
    end
  end

  private def schema_string : JSON::Any
    JSON::Any.new({
      "type" => JSON::Any.new("string"),
    } of String => JSON::Any)
  end

  private def openapi_parameter(name : String, location : String, required : Bool) : Hash(String, JSON::Any)
    {
      "name"     => JSON::Any.new(name),
      "in"       => JSON::Any.new(location),
      "required" => JSON::Any.new(required),
      "schema"   => schema_string,
    } of String => JSON::Any
  end

  private def swagger_parameter(name : String, location : String, required : Bool) : Hash(String, JSON::Any)
    {
      "name"     => JSON::Any.new(name),
      "in"       => JSON::Any.new(location),
      "type"     => JSON::Any.new("string"),
      "required" => JSON::Any.new(required),
    } of String => JSON::Any
  end

  private def swagger_url_parts(raw_url : String) : NamedTuple(host: String?, base_path: String, schemes: Array(String))
    return {host: nil, base_path: "/", schemes: %w[http https]} if raw_url.empty?

    uri = URI.parse(raw_url)
    schemes = if scheme = uri.scheme
                [scheme]
              else
                %w[http https]
              end
    base_path = uri.path.empty? ? "/" : uri.path
    base_path = "/" unless base_path.starts_with?("/")

    {host: uri.host, base_path: base_path, schemes: schemes}
  end
end
