require "../models/output_builder"
require "../models/endpoint"
require "./oas_common"
require "json"

@[Noir::OutputFormat(name: "oas3", description: "OpenAPI 3.0", order: 150, structured: true)]
class OutputBuilderOas3 < OutputBuilder
  include OutputBuilderOasCommon

  def print(endpoints : Array(Endpoint))
    paths = {} of String => Hash(String, JSON::Any)
    # Template shape (`/users/{}`) => the `paths` key that shape resolved to.
    # Two routes differing only in placeholder name are the same path item.
    canonical_paths = {} of String => String
    # Only a document that actually carries a `query` operation needs to
    # declare 3.2 — every other document stays on 3.0.3, the version every
    # other operation key here has always been valid against.
    query_operation_emitted = false

    endpoints.each do |endpoint|
      next if endpoint.non_http? # deep links / CLI commands aren't HTTP paths; keep them out of the spec
      parameters = [] of Hash(String, JSON::Any)
      json_properties = {} of String => JSON::Any
      xml_properties = {} of String => JSON::Any
      form_properties = {} of String => JSON::Any
      file_properties = {} of String => JSON::Any

      url_parts = split_route_url(endpoint.url)
      route_query = route_query_parameters(url_parts[:query], endpoint)
      route_query.each do |name, values|
        append_unique_parameter(parameters, openapi_parameter(name, "query", false, values))
      end

      endpoint.params.each do |param|
        # Already emitted above, with the value the route spells out.
        next if param.request_type == "query" && route_query.has_key?(param.name)

        case param.request_type
        when "json"
          # JSON body parameters go into requestBody
          json_properties[param.name] = schema_string
        when "form"
          # Form data parameters go into requestBody
          form_properties[param.name] = schema_string
        when "file"
          # Upload fields used to fall through to `in: query` (same class of
          # bug `body` → `json` already fixed). Postman already emits them as
          # formdata files; OAS must put them in multipart/form-data.
          file_properties[param.name] = json_any({"type" => "string", "format" => "binary"})
        when "xml"
          # Play `asXml` / Tapir `xmlBody` record a whole request body as
          # `param_type: xml` (name typically `body`). The default branch
          # used to emit `in: query`. Mirror the JSON requestBody shape
          # under `application/xml`.
          xml_properties[param.name] = schema_string
        when "header"
          # Header parameters
          append_unique_parameter(parameters, openapi_parameter(param.name, "header", false))
        when "path"
          # Path parameters
          append_unique_parameter(parameters, openapi_parameter(param.name, "path", true))
        when "cookie"
          # Cookie parameters (supported in OAS3)
          append_unique_parameter(parameters, openapi_parameter(param.name, "cookie", false))
        else
          # Default to query parameter
          append_unique_parameter(parameters, openapi_parameter(param.name, "query", false))
        end
      end

      oas_path, path_variant = resolve_oas_path(endpoint, url_parts[:route], parameters, canonical_paths)
      template_names = path_template_names(oas_path)
      template_names.each do |name|
        # A path template variable must win over a same-named query/header/
        # cookie parameter. Emitting both `in: path` and `in: query` for the
        # same name is redundant and trips strict OAS validators, so drop the
        # non-path duplicate before adding the path parameter.
        parameters.reject! { |p| p["name"].as_s == name && p["in"].as_s != "path" }
        append_unique_parameter(parameters, openapi_parameter(name, "path", true))
      end
      unmapped_path_params = extract_unmapped_path_parameters(parameters, template_names)

      # Build operation object
      operation = {
        "responses" => json_any({
          "200" => {
            "description" => "Successful response",
            "content"     => {"application/json" => {"schema" => {"type" => "object"}}},
          },
        }),
        "parameters" => JSON::Any.new(parameters.map { |p| JSON::Any.new(p) }),
      }

      request_content = {} of String => JSON::Any

      # Add requestBody for JSON content
      unless json_properties.empty?
        request_content["application/json"] = object_body(json_properties)
      end

      # Add requestBody for XML content (Play asXml / Tapir xmlBody)
      unless xml_properties.empty?
        request_content["application/xml"] = object_body(xml_properties)
      end

      # Add requestBody for form / file uploads. A file field forces
      # multipart/form-data and co-located text form fields ride along —
      # urlencoded cannot carry a binary part. File-only uploads still get
      # multipart rather than a misleading query parameter.
      if !file_properties.empty?
        request_content["multipart/form-data"] = object_body(form_properties.merge(file_properties))
      elsif !form_properties.empty?
        request_content["application/x-www-form-urlencoded"] = object_body(form_properties)
      end

      unless request_content.empty?
        operation["requestBody"] = json_any({"required" => false, "content" => request_content})
      end

      # An absolute endpoint URL names the host Noir actually found. Without
      # this the document sent every operation to the single global server, so
      # `https://demo.example.com/api/users/{id}` and
      # `https://demo.example.com.evil/api/users/{id}` merged into one
      # operation aimed at `http://localhost` — the same host loss the Postman
      # builder was fixed for. `servers` is an Operation Object field in OAS3
      # and overrides the document-level list.
      if authority = route_authority(url_parts[:route])
        operation["servers"] = json_any([{"url" => authority}])
      end

      add_operation_names_extension(operation, url_parts[:fragment])
      add_unmapped_path_params_extension(operation, unmapped_path_params)
      add_noir_callees_extension(operation, endpoint)
      add_noir_ai_context_extension(operation, endpoint)

      methods = register_operation(paths, oas_path, path_variant, endpoint.method, operation)
      query_operation_emitted = true if methods.includes?("query")
    end

    oas3_hash = {
      "openapi" => query_operation_emitted ? "3.2.0" : "3.0.3",
      "info"    => {"title" => "Generated by Noir", "version" => "1.0.0"},
      "servers" => [{"url" => target_url}],
      "paths"   => paths,
    }

    ob_puts oas3_hash.to_pretty_json
  end

  private def object_body(properties : Hash(String, JSON::Any)) : JSON::Any
    json_any({"schema" => {"type" => "object", "properties" => properties}})
  end

  # `[]?`, not `[]`: `config_initializer` seeds every key for CLI runs, but a
  # builder constructed with a partial options hash (specs, library use) hit a
  # KeyError here while the sibling oas2 builder read the same option safely.
  private def target_url : String
    document_server_url(@options["url"]?.to_s)
  end
end
