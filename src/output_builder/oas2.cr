require "../models/output_builder"
require "../models/endpoint"
require "./oas_common"
require "json"

@[Noir::OutputFormat(name: "oas2", description: "OpenAPI 2.0 (Swagger)", order: 140, structured: true)]
class OutputBuilderOas2 < OutputBuilder
  include OutputBuilderOasCommon

  # A TRACE endpoint — or any `ANY` route, which expands across every verb —
  # is reported through `x-noir-unsupported-methods` instead, the same place
  # every other verb Swagger 2.0 can't express already goes.
  private def supported_operation_methods : Set(String)
    OAS2_OPERATION_METHODS
  end

  def print(endpoints : Array(Endpoint))
    paths = {} of String => Hash(String, JSON::Any)
    # Template shape (`/users/{}`) => the `paths` key that shape resolved to.
    # Two routes differing only in placeholder name are the same path item.
    canonical_paths = {} of String => String

    endpoints.each do |endpoint|
      next if endpoint.non_http? # deep links / CLI commands aren't HTTP paths; keep them out of the spec
      parameters = [] of Hash(String, JSON::Any)
      consumes = [] of String
      cookie_names = [] of String
      json_properties = {} of String => JSON::Any
      xml_properties = {} of String => JSON::Any
      has_form = false
      has_file = false

      url_parts = split_route_url(endpoint.url)
      route_query = route_query_parameters(url_parts[:query], endpoint)
      route_query.each do |name, values|
        append_unique_parameter(parameters, swagger_parameter(name, "query", false, values))
      end

      endpoint.params.each do |param|
        # Already emitted above, with the value the route spells out.
        next if param.request_type == "query" && route_query.has_key?(param.name)

        case param.request_type
        when "json"
          # JSON body parameters should be represented as a body parameter in OAS2
          json_properties[param.name] = schema_string
          consumes << "application/json" unless consumes.includes?("application/json")
        when "form"
          # Form data parameters
          has_form = true
          append_unique_parameter(parameters, swagger_parameter(param.name, "formData", false))
          # Prefer multipart once a file field is present; otherwise urlencoded.
          unless has_file || consumes.includes?("application/x-www-form-urlencoded") || consumes.includes?("multipart/form-data")
            consumes << "application/x-www-form-urlencoded"
          end
        when "file"
          # Upload fields used to fall through to `in: query`. Swagger 2.0
          # represents them as `formData` with `type: file` under multipart.
          has_file = true
          has_form = true
          append_unique_parameter(parameters, json_any({"name" => param.name, "in" => "formData", "type" => "file", "required" => false}).as_h)
          consumes.reject! { |c| c == "application/x-www-form-urlencoded" }
          consumes << "multipart/form-data" unless consumes.includes?("multipart/form-data")
        when "xml"
          # Play `asXml` / Tapir `xmlBody` record a whole request body as
          # `param_type: xml` (name typically `body`). The default branch
          # used to emit `in: query`, so `/xml` looked like `?body=` while
          # `-f json` kept `param_type: xml`. Mirror the JSON body shape
          # under `application/xml`.
          xml_properties[param.name] = schema_string
          consumes << "application/xml" unless consumes.includes?("application/xml")
        when "header"
          # Header parameters
          append_unique_parameter(parameters, swagger_parameter(param.name, "header", false))
        when "path"
          # Path parameters
          append_unique_parameter(parameters, swagger_parameter(param.name, "path", true))
        when "cookie"
          # Collect cookie names for later
          cookie_names << param.name
        else
          # Default to query parameter
          append_unique_parameter(parameters, swagger_parameter(param.name, "query", false))
        end
      end

      oas_path, path_variant = resolve_oas_path(endpoint, url_parts[:route], parameters, canonical_paths)
      template_names = path_template_names(oas_path)
      template_names.each do |name|
        # A path template variable wins over a same-named query/header
        # parameter, as it does in the OAS3 builder. `formData` and `body` are
        # left alone: they are request-payload fields, not another spelling of
        # the same path segment.
        parameters.reject! { |p| p["name"].as_s == name && {"query", "header"}.includes?(p["in"].as_s) }
        append_unique_parameter(parameters, swagger_parameter(name, "path", true))
      end

      # Add single Cookie header parameter if cookies exist
      # Cookies are not directly supported in OAS2, typically sent as Cookie header
      unless cookie_names.empty?
        cookie_desc = "Cookies: " + cookie_names.map { |name| "#{name}=<value>" }.join("; ")
        # Header names are case-insensitive (RFC 9110), so a header-type param
        # already named `Cookie`/`cookie` occupies this very slot. Swagger 2.0
        # keys parameter uniqueness on name+in, so appending unconditionally
        # put two `{in: header, name: Cookie}` entries in one operation and the
        # document stopped validating. Replace it — the synthesized entry is
        # the one that names the cookies. (Mirrors the postman builder's
        # case-insensitive cookie merge.)
        parameters.reject! { |p| p["in"].as_s == "header" && p["name"].as_s.downcase == "cookie" }
        parameters << json_any({"name" => "Cookie", "in" => "header", "type" => "string", "required" => false, "description" => cookie_desc}).as_h
      end

      # Add body parameter for JSON / XML content.
      # OAS2 does not allow body and formData parameters in the same operation.
      # If both are present, keep the formData shape because it preserves the
      # concrete field names as request parameters.
      body_properties = json_properties.merge(xml_properties)
      if !body_properties.empty? && !has_form
        append_unique_parameter(parameters, json_any({
          "name"     => "body",
          "in"       => "body",
          "required" => false,
          "schema"   => {"type" => "object", "properties" => body_properties},
        }).as_h)
      elsif !body_properties.empty? && has_form
        # OAS2 forbids `body` and `formData` in the same operation, so the
        # JSON/XML body is dropped in favor of the concrete formData fields.
        # Rather than losing the field names entirely, surface each as a query
        # parameter (query + formData are allowed together) so they survive.
        body_properties.each_key do |name|
          append_unique_parameter(parameters, swagger_parameter(name, "query", false))
        end
      end

      if has_form
        consumes.reject! { |content_type| {"application/json", "application/xml"}.includes?(content_type) }
      end

      unmapped_path_params = extract_unmapped_path_parameters(parameters, template_names)

      # Build operation object
      operation = {
        "responses"  => json_any({"200" => {"description" => "Successful response"}}),
        "parameters" => JSON::Any.new(parameters.map { |p| JSON::Any.new(p) }),
      }

      # Add consumes if present
      unless consumes.empty?
        operation["consumes"] = json_any(consumes)
      end

      # Swagger 2.0 has one document-level `host`, with no per-operation
      # override to put an absolute endpoint's real host in (OAS3 has
      # `servers`, which the oas3 builder uses). Recording it as an extension
      # at least stops the host Noir found from disappearing when two
      # different hosts collapse onto one path+method.
      if authority = route_authority(url_parts[:route])
        operation["x-noir-hosts"] = json_any([authority])
      end

      add_operation_names_extension(operation, url_parts[:fragment])
      add_unmapped_path_params_extension(operation, unmapped_path_params)
      add_noir_callees_extension(operation, endpoint)
      add_noir_ai_context_extension(operation, endpoint)

      register_operation(paths, oas_path, path_variant, endpoint.method, operation)
    end

    url_parts = swagger_url_parts(@options["url"]?.try(&.to_s) || "")
    oas2_hash = {
      "swagger" => "2.0",
      "info"    => {"title" => "Generated by Noir", "version" => "1.0.0"},
      # `-u`'s path already prefixes every `paths` key (see
      # `swagger_url_parts`), so the document's base is the authority alone.
      "basePath" => "/",
      "schemes"  => url_parts[:schemes],
      "produces" => ["application/json"],
      "paths"    => paths,
    }

    if host = url_parts[:host]
      oas2_hash["host"] = host
    end

    ob_puts oas2_hash.to_pretty_json
  end
end
