require "json"
require "uri"
require "../utils/http_symbols"

module OutputBuilderOasCommon
  VALID_OPERATION_METHODS = Set{"get", "put", "post", "delete", "options", "head", "patch", "trace"}
  ANY_OPERATION_METHODS   = WILDCARD_HTTP_METHODS.map(&.downcase)

  # Swagger 2.0's Path Item Object has no `trace` field — `trace` arrived with
  # OpenAPI 3.0. Emitting one made the *whole document* invalid, not just that
  # operation, and an `ANY` route expands across every verb, so this hit 25 of
  # the fixture tree's OAS2 documents.
  OAS2_OPERATION_METHODS = VALID_OPERATION_METHODS - Set{"trace"}

  # Converter names that can appear in a `<…>` path placeholder. Same list the
  # optimizer's `angle_bracket_param` uses, so the two resolve a placeholder
  # the same way.
  PATH_CONVERTER_TYPES = Set{"int", "str", "string", "slug", "uuid", "float", "bool", "path"}

  # Operation keys whose value is a list of alternatives rather than a single
  # answer. When two endpoints collapse onto one path+method, keeping the
  # first one's value throws the rest away — `servers` would name one of two
  # hosts, `x-noir-operations` one of fifteen GraphQL operations — so these
  # are unioned instead.
  UNIONED_OPERATION_KEYS = Set{"servers", "x-noir-operations", "x-noir-hosts"}

  # `declared_path_params` are the names the endpoint itself records as
  # `param_type == "path"`. They disambiguate `<a:b>` placeholders, whose two
  # halves are spelled in either order depending on the framework.
  #
  # Takes the route's path (see `OutputBuilder#route_path`), not the raw URL:
  # this used to run `URI.parse(raw_url).path`, which truncated a route at the
  # first `?` even when the `?` was regex or optional-segment syntax rather
  # than a query separator — Drogon's `/grp/(?:a|b)/(.*)?` emitted the path
  # `/grp/(` and Giraffe's `/legacy(/?)` emitted `/legacy(/`.
  private def normalize_oas_path(raw_path : String, declared_path_params : Array(String) = [] of String) : String
    path = raw_path
    path = "/" if path.empty?

    # Google AIP / gRPC-transcoding resource patterns (`{name=projects/*}`)
    # embed a path pattern inside the placeholder. Left alone, the `*` pass
    # below turned it into the nested, unbalanced `{name=projects/{wildcard}}`
    # — no longer a path template at all. The variable is `name`; the pattern
    # only says what it matches.
    path = path.gsub(/\{(\w+)=[^{}]*\}/, "{\\1}")

    # Express-style optional segments (`/:id{/:op}`) are not representable as
    # optional in OpenAPI path templates. Drop the route-syntax braces so the
    # emitted path remains a valid template instead of `/users/{id}{/{op}}`.
    path = path.gsub(/\{\/:(\w+)\}/, "/:\\1")
    path = path.gsub(/\{\/([^{}]+)\}/, "/\\1")

    # Bracket-style path params (`.NET` / Rails-ish `/users/[id]`) → `{id}`.
    path = path.gsub(/\[(\w+)\]/, "{\\1}")

    # Play's routes file spells a constrained param `$path<.+>`. The regex is
    # a constraint, not a name, and neither `<…>` pass below matches it, so
    # the placeholder used to survive verbatim into the emitted path.
    path = path.gsub(/\$(\w+)<[^<>]*>/, "{\\1}")

    # Convert typed placeholders before the generic :param pass; otherwise
    # `<int:id>` becomes `<int{id}>` and can no longer be normalized.
    path = path.gsub(/<([^:<>]+):(\w+)>/) do |_, match|
      "{#{angle_placeholder_name(match[1], match[2], declared_path_params)}}"
    end
    path = path.gsub(/<(\w+)>/, "{\\1}")

    # Catch-all placeholders keep the rest-of-path marker inside the braces:
    # Armeria `{*filePath}`, Salvo `{**path}`, ASP.NET and Spring `{*slug}`.
    # The variable is the name; the stars only say how much of the path it
    # eats — which a path template has no way to express anyway. Without this
    # the `*` passes below ran *inside* the existing placeholder and produced
    # the nested, unbalanced `{{filePath}}` and `{{wildcard}{path}}`: not path
    # templates at all, and their declared `filePath` / `path` parameters no
    # longer bound to anything.
    path = path.gsub(/\{\*+(\w+)\}/, "{\\1}")

    path = path.gsub(/\*(\w+)/, "{\\1}")
    path = path.gsub(/:(\w+)/, "{\\1}")

    # Bare wildcard segments (`/api/*`, `/files/**`) have no name and are not
    # a valid OAS path template char; collapse a run of `*` to a named var.
    # Two of them in one path (`/api/*/v1/*`) have to get distinct names —
    # a repeated template variable is not a valid path template.
    wildcards = 0
    path = path.gsub(/\*+/) do
      wildcards += 1
      wildcards == 1 ? "{wildcard}" : "{wildcard#{wildcards}}"
    end

    # A `?` that reaches here is route syntax a path template has no way to
    # carry — an optional segment (`/geo/:ip?`) or a regex group
    # (`/items(?:/(\d+))?`). Drop it: a literal `?` in a path key opens a
    # query string the moment the key is appended to a server URL.
    path = path.delete('?')

    path.starts_with?("/") ? path : "/#{path}"
  end

  # Resolve the parameter name in a `<head:tail>` placeholder. Both orderings
  # are in the wild: Django and Flask spell it `<int:id>` (converter first)
  # while Sanic, Bottle and Marten spell it `<id:int>` (name first). Always
  # taking the second half named every Sanic route after its converter —
  # `/users/<id:int>` emitted `{int}`, and two routes sharing a converter
  # (`/metrics/<metric_id:int>`, `/reports/<report_id:int>`) collapsed onto
  # the same OAS path.
  #
  # The endpoint's own path params are the authoritative signal: the optimizer
  # resolved the same placeholder when it registered them. The converter list
  # only decides placeholders they don't cover, and when both halves name a
  # converter (`<slug:str>`) the Django ordering wins — it is by far the more
  # common of the two.
  private def angle_placeholder_name(head : String, tail : String, declared : Array(String)) : String
    return head if declared.includes?(head)
    return tail if declared.includes?(tail)
    # Converter arguments (`<int(min=1):id>`) aren't part of the type name.
    return tail if PATH_CONVERTER_TYPES.includes?(head.split('(', 2)[0])
    return head if PATH_CONVERTER_TYPES.includes?(tail)

    tail
  end

  # The route's own query string and any declared query param of the same
  # name describe one parameter, and `bake_endpoint` already settled how they
  # relate: a pair the route spells verbatim adds nothing, while a *different*
  # value for the same name is an override worth keeping. Resolved up front,
  # in route order, so a value-less declaration (the usual case — the analyzer
  # records `action` because the route spells `action=get_user_data`) cannot
  # erase the value the route carries.
  #
  # Returns name => concrete values, empty array meaning unconstrained.
  private def route_query_parameters(route_query : Array(Tuple(String, String)), endpoint : Endpoint) : Hash(String, Array(String))
    resolved = {} of String => Array(String)

    route_query.each do |name, value|
      values = resolved[name] ||= [] of String
      values << value unless value.empty? || values.includes?(value)
    end

    endpoint.params.each do |param|
      next unless param.request_type == "query"
      values = resolved[param.name]?
      next if values.nil? || param.value.empty?

      values << param.value unless values.includes?(param.value)
    end

    resolved
  end

  private def path_template_names(path : String) : Array(String)
    names = path.scan(/\{([^{}\/]+)\}/).map { |match| match[1] }
    names.uniq!
    names
  end

  # The operation fields the emitted version's Path Item Object accepts.
  # Overridden by the OAS2 builder, which has no `trace`.
  private def supported_operation_methods : Set(String)
    VALID_OPERATION_METHODS
  end

  private def operation_methods(method : String) : Array(String)
    supported = supported_operation_methods
    normalized = method.downcase
    return [normalized] if supported.includes?(normalized)

    if {"any", "all", "forward", "use"}.includes?(normalized)
      return ANY_OPERATION_METHODS.select { |candidate| supported.includes?(candidate) }
    end

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
    if index = parameters.index { |existing| parameter_key(existing) == key }
      parameters[index] = merge_parameter(parameters[index], parameter)
      return
    end

    parameters << parameter
  end

  # A repeated name+in is not always redundant. Two routes that differ only in
  # a value their path key can't hold — `admin-ajax.php?action=get_user_data`
  # and `?action=save_settings`, two different WordPress AJAX handlers —
  # collapse onto one path+method, and keeping the first parameter dropped
  # every other handler's address. Union the enumerated values instead.
  #
  # A parameter with no enum is unconstrained, and unconstrained wins: if one
  # route pins `action` to a value and another accepts anything, the merged
  # operation accepts anything.
  private def merge_parameter(existing : Hash(String, JSON::Any), incoming : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
    existing_values = parameter_enum(existing)
    incoming_values = parameter_enum(incoming)
    return with_parameter_enum(existing, nil) unless existing_values && incoming_values

    with_parameter_enum(existing, existing_values | incoming_values)
  end

  # OAS3 nests the constraint under `schema`, Swagger 2.0 puts it on the
  # parameter itself. Both builders share the merge, so both shapes are read
  # and written through here.
  private def enum_container(parameter : Hash(String, JSON::Any)) : Hash(String, JSON::Any)?
    parameter["schema"]?.try(&.as_h?)
  end

  private def parameter_enum(parameter : Hash(String, JSON::Any)) : Array(String)?
    container = enum_container(parameter) || parameter
    container["enum"]?.try(&.as_a?).try(&.map(&.as_s))
  end

  private def with_parameter_enum(parameter : Hash(String, JSON::Any), values : Array(String)?) : Hash(String, JSON::Any)
    result = parameter.dup
    encoded = values.try { |list| JSON::Any.new(list.map { |value| JSON::Any.new(value) }) }

    if schema = enum_container(result)
      schema = schema.dup
      encoded ? (schema["enum"] = encoded) : schema.delete("enum")
      result["schema"] = JSON::Any.new(schema)
    else
      encoded ? (result["enum"] = encoded) : result.delete("enum")
    end

    result
  end

  # The `#fragment` Noir uses to address many operations on one path. An OAS
  # path key cannot hold it and the request really is a single
  # `POST /graphql`, so the operations are correctly merged — but their names
  # were merged away with them: 15 Hasura operations became one
  # `POST /v1/graphql` with nothing left saying what could be called, and 41
  # operations vanished from the fixture tree's documents altogether.
  private def add_operation_names_extension(operation : Hash(String, JSON::Any), name : String?)
    return unless name

    operation["x-noir-operations"] = JSON::Any.new([JSON::Any.new(name)])
  end

  private def union_json_arrays(existing : JSON::Any, incoming : JSON::Any) : JSON::Any
    merged = existing.as_a.dup
    incoming.as_a.each do |item|
      merged << item unless merged.any? { |seen| seen == item }
    end

    JSON::Any.new(merged)
  end

  # Both OAS2 and OAS3 require an `in: path` parameter to correspond to a
  # template expression in the path, so a declared path param the emitted path
  # can't express makes the whole document fail validation. Analyzers produce
  # those routinely: a Rails route whose placeholder the optimizer replaced
  # with a concrete value (`/posts/1` still reads `id`), a splat literally
  # named `*`, a param resolved from another file for an otherwise static
  # route. Drop them from `parameters` and hand the names back so the caller
  # can keep them in an extension instead of losing them.
  private def extract_unmapped_path_parameters(parameters : Array(Hash(String, JSON::Any)), template_names : Array(String)) : Array(String)
    unmapped = [] of String

    parameters.reject! do |parameter|
      next false unless parameter["in"].as_s == "path"

      name = parameter["name"].as_s
      next false if template_names.includes?(name)

      unmapped << name
      true
    end

    unmapped
  end

  private def add_unmapped_path_params_extension(operation : Hash(String, JSON::Any), names : Array(String))
    return if names.empty?

    operation["x-noir-unmapped-path-params"] = JSON::Any.new(names.map { |name| JSON::Any.new(name) })
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

      if UNIONED_OPERATION_KEYS.includes?(key) && (existing_value = merged[key]?)
        merged[key] = union_json_arrays(existing_value, value)
      else
        merged[key] = value unless merged.has_key?(key)
      end
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

  # `values` are the concrete values a route spells out for the parameter,
  # recorded as an `enum` so they survive into the document — otherwise
  # `/wp-admin/admin-ajax.php?action=get_user_data` documents an `action`
  # parameter with no hint that `get_user_data` is what reaches the handler.
  # No values means unconstrained.
  private def enum_values(values : Array(String)?) : Array(JSON::Any)?
    return if values.nil? || values.empty?

    values.map { |value| JSON::Any.new(value) }
  end

  private def openapi_parameter(name : String, location : String, required : Bool, values : Array(String)? = nil) : Hash(String, JSON::Any)
    schema = schema_string
    if encoded = enum_values(values)
      schema = JSON::Any.new({
        "type" => JSON::Any.new("string"),
        "enum" => JSON::Any.new(encoded),
      } of String => JSON::Any)
    end

    {
      "name"     => JSON::Any.new(name),
      "in"       => JSON::Any.new(location),
      "required" => JSON::Any.new(required),
      "schema"   => schema,
    } of String => JSON::Any
  end

  private def swagger_parameter(name : String, location : String, required : Bool, values : Array(String)? = nil) : Hash(String, JSON::Any)
    parameter = {
      "name"     => JSON::Any.new(name),
      "in"       => JSON::Any.new(location),
      "type"     => JSON::Any.new("string"),
      "required" => JSON::Any.new(required),
    } of String => JSON::Any

    if encoded = enum_values(values)
      parameter["enum"] = JSON::Any.new(encoded)
    end

    parameter
  end

  private def swagger_url_parts(raw_url : String) : NamedTuple(host: String?, base_path: String, schemes: Array(String))
    return {host: nil, base_path: "/", schemes: %w[http https]} if raw_url.empty?

    # A scheme-less `-u example.com` makes URI.parse read the whole value as a
    # path (host=nil), so the Swagger `host` field was dropped. Prepend a
    # scheme for parsing so the authority resolves into uri.host; the emitted
    # scheme list still defaults to http+https since the user gave none.
    had_scheme = raw_url.includes?("://")
    uri = URI.parse(had_scheme ? raw_url : "http://#{raw_url}")
    schemes = if had_scheme && (scheme = uri.scheme)
                [scheme]
              else
                %w[http https]
              end
    base_path = uri.path.empty? ? "/" : uri.path
    base_path = "/" unless base_path.starts_with?("/")

    {host: uri.host, base_path: base_path, schemes: schemes}
  end
end
