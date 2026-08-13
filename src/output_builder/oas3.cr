require "../models/output_builder"
require "../models/endpoint"
require "./oas_common"
require "json"

@[Noir::OutputFormat(name: "oas3", description: "OpenAPI 3.0", order: 150, structured: true)]
class OutputBuilderOas3 < OutputBuilder
  include OutputBuilderOasCommon

  def print(endpoints : Array(Endpoint))
    paths = {} of String => Hash(String, JSON::Any)

    endpoints.each do |endpoint|
      next if endpoint.non_http? # deep links / CLI commands aren't HTTP paths; keep them out of the spec
      parameters = [] of Hash(String, JSON::Any)
      json_properties = {} of String => JSON::Any
      form_properties = {} of String => JSON::Any

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
          json_properties[param.name] = JSON::Any.new({
            "type" => JSON::Any.new("string"),
          } of String => JSON::Any)
        when "form"
          # Form data parameters go into requestBody
          form_properties[param.name] = JSON::Any.new({
            "type" => JSON::Any.new("string"),
          } of String => JSON::Any)
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

      declared_path_params = endpoint.params.compact_map { |p| p.name if p.request_type == "path" }
      oas_path = normalize_oas_path(route_path(url_parts[:route]), declared_path_params)
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
        "responses" => JSON::Any.new({
          "200" => JSON::Any.new({
            "description" => JSON::Any.new("Successful response"),
            "content"     => JSON::Any.new({
              "application/json" => JSON::Any.new({
                "schema" => JSON::Any.new({
                  "type" => JSON::Any.new("object"),
                } of String => JSON::Any),
              } of String => JSON::Any),
            } of String => JSON::Any),
          } of String => JSON::Any),
        } of String => JSON::Any),
        "parameters" => JSON::Any.new(parameters.map { |p| JSON::Any.new(p) }),
      } of String => JSON::Any

      request_content = {} of String => JSON::Any

      # Add requestBody for JSON content
      unless json_properties.empty?
        request_content["application/json"] = JSON::Any.new({
          "schema" => JSON::Any.new({
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new(json_properties),
          } of String => JSON::Any),
        } of String => JSON::Any)
      end

      # Add requestBody for form data
      unless form_properties.empty?
        request_content["application/x-www-form-urlencoded"] = JSON::Any.new({
          "schema" => JSON::Any.new({
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new(form_properties),
          } of String => JSON::Any),
        } of String => JSON::Any)
      end

      unless request_content.empty?
        operation["requestBody"] = JSON::Any.new({
          "required" => JSON::Any.new(false),
          "content"  => JSON::Any.new(request_content),
        } of String => JSON::Any)
      end

      # An absolute endpoint URL names the host Noir actually found. Without
      # this the document sent every operation to the single global server, so
      # `https://demo.example.com/api/users/{id}` and
      # `https://demo.example.com.evil/api/users/{id}` merged into one
      # operation aimed at `http://localhost` — the same host loss the Postman
      # builder was fixed for. `servers` is an Operation Object field in OAS3
      # and overrides the document-level list.
      if authority = route_authority(url_parts[:route])
        operation["servers"] = JSON::Any.new([
          JSON::Any.new({"url" => JSON::Any.new(authority)} of String => JSON::Any),
        ])
      end

      add_operation_names_extension(operation, url_parts[:fragment])
      add_unmapped_path_params_extension(operation, unmapped_path_params)
      add_noir_callees_extension(operation, endpoint)
      add_noir_ai_context_extension(operation, endpoint)

      # Initialize path if not exists
      unless paths.has_key?(oas_path)
        paths[oas_path] = {} of String => JSON::Any
      end

      # Add method to path
      methods = operation_methods(endpoint.method)
      if methods.empty?
        add_unsupported_method_extension(paths[oas_path], endpoint.method)
      else
        methods.each do |method|
          add_operation(paths[oas_path], method, operation)
        end
      end
    end

    oas3_hash = {
      "openapi" => JSON::Any.new("3.0.3"),
      "info"    => JSON::Any.new({
        "title"   => JSON::Any.new("Generated by Noir"),
        "version" => JSON::Any.new("1.0.0"),
      } of String => JSON::Any),
      "servers" => JSON::Any.new([
        JSON::Any.new({
          "url" => JSON::Any.new(target_url),
        } of String => JSON::Any),
      ]),
      "paths" => JSON::Any.new(paths.transform_values { |v| JSON::Any.new(v) }),
    } of String => JSON::Any

    ob_puts JSON::Any.new(oas3_hash).to_pretty_json
  end

  # `[]?`, not `[]`: `config_initializer` seeds every key for CLI runs, but a
  # builder constructed with a partial options hash (specs, library use) hit a
  # KeyError here while the sibling oas2 builder read the same option safely.
  private def target_url : String
    url = @options["url"]?.to_s
    url.empty? ? "http://localhost" : url
  end
end
