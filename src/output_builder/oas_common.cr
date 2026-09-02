require "json"
require "uri"
require "../utils/http_symbols"

module OutputBuilderOasCommon
  # The operation keys a Path Item Object accepts. `query` (RFC 10008)
  # arrived with OpenAPI 3.2, so the oas3 builder only emits it as a real
  # operation key — bumping the document's declared `openapi` version to
  # 3.2.0 when (and only when) it does; every other emitted document stays on
  # 3.0.3. Swagger 2.0 has no later version to adopt `query` into and can
  # never express it, so `OAS2_OPERATION_METHODS` below excludes it and a
  # QUERY endpoint keeps degrading to the `x-noir-unsupported-methods`
  # extension rather than being dropped or downgraded to `get`.
  VALID_OPERATION_METHODS = Set{"get", "put", "post", "delete", "options", "head", "patch", "trace", "query"}
  ANY_OPERATION_METHODS   = WILDCARD_HTTP_METHODS.map(&.downcase)

  # Swagger 2.0's Path Item Object has no `trace` field (arrived with OpenAPI
  # 3.0) and no `query` field (arrived with OpenAPI 3.2, a version Swagger 2.0
  # will never advance to). Emitting either made the *whole document* invalid,
  # not just that operation, and an `ANY` route expands across every verb, so
  # `trace` alone hit 25 of the fixture tree's OAS2 documents.
  OAS2_OPERATION_METHODS = VALID_OPERATION_METHODS - Set{"trace", "query"}

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
    names = path_template_name_sequence(path)
    names.uniq!
    names
  end

  # Every template variable in the order it appears, duplicates included —
  # what `canonical_oas_path` needs to line two same-shaped paths up slot by
  # slot. `path_template_names` de-duplicates and would misalign the two
  # lists the moment a route repeats a variable.
  private def path_template_name_sequence(path : String) : Array(String)
    path.scan(/\{([^{}\/]+)\}/).map { |match| match[1] }
  end

  # The path with every template variable's *name* erased. Both OAS 2.0 and
  # OAS 3.x say two templated paths with the same hierarchy but different
  # variable names are identical and MUST NOT both appear, so `/users/{id}`
  # and `/users/{userId}` name one path item — keying `paths` on the literal
  # string made them siblings and Spectral, Swagger Editor and
  # `openapi-spec-validator` all rejected the document over it. Nine of the
  # fixture tree's single-framework directories produce such a pair.
  private def path_template_shape(path : String) : String
    path.gsub(/\{[^{}\/]+\}/, "{}")
  end

  # The `paths` key an emitted path belongs under: itself the first time its
  # shape is seen, the earlier path of that shape afterwards. `paths` keeps
  # insertion order and endpoints arrive sorted, so the winner is stable
  # across runs.
  private def canonical_oas_path(oas_path : String, canonical_paths : Hash(String, String)) : String
    canonical_paths[path_template_shape(oas_path)] ||= oas_path
  end

  # Maps the incoming path's variable names onto the canonical path's, slot
  # by slot. The two share a template shape, so the sequences are the same
  # length; a name that repeats keeps its first mapping.
  private def path_template_renames(from : String, to : String) : Hash(String, String)
    incoming = path_template_name_sequence(from)
    canonical = path_template_name_sequence(to)
    renames = {} of String => String

    incoming.each_with_index do |name, index|
      canonical_name = canonical[index]?
      next if canonical_name.nil? || canonical_name == name

      renames[name] ||= canonical_name
    end

    renames
  end

  # Rewrites path parameters onto the canonical path's variable names.
  # Without this the merged operation declares `in: path, name: userId`
  # against a `/users/{id}` template — a path parameter bound to nothing,
  # which is exactly the validation error the merge exists to remove.
  private def rename_path_parameters(parameters : Array(Hash(String, JSON::Any)), renames : Hash(String, String))
    return if renames.empty?

    renamed = [] of Hash(String, JSON::Any)
    parameters.each do |parameter|
      if parameter["in"].as_s == "path" && (name = renames[parameter["name"].as_s]?)
        parameter = parameter.dup
        parameter["name"] = JSON::Any.new(name)
      end

      append_unique_parameter(renamed, parameter)
    end

    parameters.replace(renamed)
  end

  # The alternate spellings folded into a path item, so merging two routes
  # that differ only in placeholder name loses no information: the document
  # says `/users/{id}`, the extension says one of the routes behind it was
  # written `/users/{userId}`.
  private def add_path_variant_extension(path_item : Hash(String, JSON::Any), variant : String)
    variants = [] of String
    if existing = path_item["x-noir-path-variants"]?
      variants = existing.as_a.map(&.as_s)
    end

    return if variants.includes?(variant)

    variants << variant
    path_item["x-noir-path-variants"] = JSON::Any.new(variants.map { |name| JSON::Any.new(name) })
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

  # The operation a verb the emitted version can't express would have had.
  # Recording only the verb name threw the whole operation away —
  # parameters, request body, `servers`, `x-noir-callees`,
  # `x-noir-ai-context` — so every `TRACE`/`QUERY` route on Swagger 2.0 and
  # every AsyncAPI `SEND`/`PUBLISH`/`SUBSCRIBE`/`RECEIVE` endpoint on both
  # versions reached the document as a bare verb string with none of its
  # data. Keyed by the verb as the analyzer spelled it, merged the same way
  # a real operation is when two endpoints collapse onto one.
  private def add_unsupported_operation(path_item : Hash(String, JSON::Any), method : String, operation : Hash(String, JSON::Any))
    promote_path_parameters_to_item(path_item, operation)
    operations = path_item["x-noir-unsupported-operations"]?.try(&.as_h?).try(&.dup) || {} of String => JSON::Any

    if existing = operations[method]?
      operations[method] = merge_operations(existing, operation)
    else
      operations[method] = JSON::Any.new(operation)
    end

    path_item["x-noir-unsupported-operations"] = JSON::Any.new(operations)
  end

  # Path templating requires every `{name}` in the path to be declared "in the
  # Path Item Object itself and/or in each Operation's parameters". An
  # operation parked under `x-noir-unsupported-operations` is an extension —
  # no validator reads parameters out of it — so a path whose only verbs are
  # unsupported ones declared none at all: `/app/chat/send/{roomId}`, a STOMP
  # `SEND` route, left `{roomId}` dangling and the document invalid. The Path
  # Item is where a parameter shared by every operation belongs, and putting
  # it there satisfies the rule without inventing an operation the verb
  # cannot have.
  private def promote_path_parameters_to_item(path_item : Hash(String, JSON::Any), operation : Hash(String, JSON::Any))
    operation_parameters = operation["parameters"]?.try(&.as_a?)
    return unless operation_parameters

    parameters = path_item["parameters"]?.try(&.as_a?).try(&.compact_map(&.as_h?)) || [] of Hash(String, JSON::Any)
    added = false

    operation_parameters.each do |raw|
      parameter = raw.as_h?
      next unless parameter
      next unless parameter["in"]?.try(&.as_s?) == "path"
      next if parameters.any? { |existing| parameter_key(existing) == parameter_key(parameter) }

      parameters << parameter
      added = true
    end

    return unless added

    path_item["parameters"] = JSON::Any.new(parameters.map { |parameter| JSON::Any.new(parameter) })
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
    # Swagger 2.0 carries the request body as a parameter, and its `schema`
    # is an object of properties rather than the enum container the rest of
    # this method reads. Falling through here returned the first operation's
    # body verbatim and dropped every later one's fields.
    return merge_body_parameter(existing, incoming) if existing["in"]?.try(&.as_s?) == "body"

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

  private def merge_body_parameter(existing : Hash(String, JSON::Any), incoming : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
    merged = existing.dup
    if schema = merge_schema(merged["schema"]?, incoming["schema"]?)
      merged["schema"] = schema
    end

    merged
  end

  # Noir addresses many operations on one path with a `#fragment` — GraphQL
  # resolvers, JSON-RPC methods — so they all legitimately collapse onto one
  # `POST /graphql`. Keeping the first schema and discarding the rest lost
  # every later operation's input fields: 62 json parameters vanished from
  # the specification fixtures' documents alone. `x-noir-operations` was
  # already unioned so the document *named* operations whose inputs it no
  # longer described.
  private def merge_schema(existing : JSON::Any?, incoming : JSON::Any?) : JSON::Any?
    return incoming unless existing
    return existing unless incoming

    existing_hash = existing.as_h?
    incoming_hash = incoming.as_h?
    return existing unless existing_hash && incoming_hash

    merged = existing_hash.dup
    existing_properties = merged["properties"]?.try(&.as_h?)
    incoming_properties = incoming_hash["properties"]?.try(&.as_h?)

    if existing_properties && incoming_properties
      properties = existing_properties.dup
      incoming_properties.each do |name, value|
        properties[name] = value unless properties.has_key?(name)
      end
      merged["properties"] = JSON::Any.new(properties)
    elsif incoming_properties
      merged["properties"] = JSON::Any.new(incoming_properties)
    end

    # `required` is a claim about one request. A field only one of the merged
    # operations demands is not mandatory for the path+method as a whole, so
    # the merged list is the intersection — the union would make callers of
    # `Query.users` send `Mutation.createUser`'s fields.
    existing_required = merged["required"]?.try(&.as_a?)
    incoming_required = incoming_hash["required"]?.try(&.as_a?)
    if existing_required && incoming_required
      merged["required"] = JSON::Any.new(existing_required.select { |name| incoming_required.includes?(name) })
    elsif existing_required
      merged.delete("required")
    end

    JSON::Any.new(merged)
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
          existing_media = content[media_type]?
          content[media_type] = existing_media ? merge_media_type(existing_media, media_value) : media_value
        end
        existing_hash["content"] = JSON::Any.new(content)
      end
    elsif incoming_content = incoming_hash["content"]?
      existing_hash["content"] = incoming_content
    end

    JSON::Any.new(existing_hash)
  end

  private def merge_media_type(existing : JSON::Any, incoming : JSON::Any) : JSON::Any
    existing_hash = existing.as_h?
    incoming_hash = incoming.as_h?
    return existing unless existing_hash && incoming_hash

    merged = existing_hash.dup
    if schema = merge_schema(merged["schema"]?, incoming_hash["schema"]?)
      merged["schema"] = schema
    end

    incoming_hash.each do |key, value|
      next if key == "schema"

      merged[key] = value unless merged.has_key?(key)
    end

    JSON::Any.new(merged)
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

  # The authority and scheme list `-u` names.
  #
  # No `base_path`: `-u` is prepended to every endpoint URL by the optimizer,
  # so its path component is already part of every `paths` key. Declaring it
  # a second time as Swagger's `basePath` (or OAS3's `servers[0].url`) made
  # every operation resolve to `<base><base><path>` — `-u https://h/v2`
  # documented `https://h/v2/v2/users` where `-f curl`, on the same run and
  # the same endpoint, printed `https://h/v2/users`. The per-operation
  # `servers` entry an absolute endpoint gets carries the authority alone, so
  # the document-level base has to agree with it and carry no path either.
  private def swagger_url_parts(raw_url : String) : NamedTuple(host: String?, schemes: Array(String))
    return {host: nil, schemes: %w[http https]} if raw_url.empty?

    # A scheme-less `-u example.com` makes URI.parse read the whole value as a
    # path (host=nil), so the Swagger `host` field was dropped. Prepend a
    # scheme for parsing so the authority resolves into uri.host; the emitted
    # scheme list still defaults to http+https since the user gave none.
    had_scheme = raw_url.includes?("://")
    uri = URI.parse(had_scheme ? raw_url : "http://#{raw_url}")
    scheme = uri.scheme
    schemes = if had_scheme && scheme
                [scheme]
              else
                %w[http https]
              end

    host = uri.host
    host = nil if host.try(&.empty?)
    # Swagger 2.0's `host` is `host[:port]`. Dropping the port sent every
    # generated client and every Swagger-UI "Try it out" to 443/80 instead of
    # the port `-u` named, while `-f oas3` and `-f postman` both kept it. A
    # port that only restates the scheme's default adds nothing, so
    # `https://x/` stays `x` rather than becoming `x:443`.
    if host && (port = uri.port) && port != URI.default_port(scheme || "http")
      host = "#{host}:#{port}"
    end

    {host: host, schemes: schemes}
  end

  # The document-level server URL: `-u`'s scheme and authority, with its path
  # stripped for the reason `swagger_url_parts` explains. Falls back to `/`
  # when `-u` names no authority to build one from — the path is already in
  # every `paths` key either way.
  private def document_server_url(raw_url : String) : String
    return "http://localhost" if raw_url.empty?

    parts = swagger_url_parts(raw_url)
    host = parts[:host]
    return "/" unless host

    "#{parts[:schemes].first}://#{host}"
  end
end
