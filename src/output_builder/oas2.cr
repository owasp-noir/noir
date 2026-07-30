require "../models/output_builder"
require "../models/endpoint"
require "./oas_common"
require "json"

class OutputBuilderOas2 < OutputBuilder
  include OutputBuilderOasCommon

  def print(endpoints : Array(Endpoint))
    paths = {} of String => Hash(String, JSON::Any)

    endpoints.each do |endpoint|
      next if endpoint.non_http? # deep links / CLI commands aren't HTTP paths; keep them out of the spec
      parameters = [] of Hash(String, JSON::Any)
      consumes = [] of String
      cookie_names = [] of String
      json_properties = {} of String => JSON::Any
      has_form = false

      endpoint.params.each do |param|
        case param.param_type
        when "json"
          # JSON body parameters should be represented as a body parameter in OAS2
          json_properties[param.name] = JSON::Any.new({
            "type" => JSON::Any.new("string"),
          } of String => JSON::Any)
          consumes << "application/json" unless consumes.includes?("application/json")
        when "form"
          # Form data parameters
          has_form = true
          append_unique_parameter(parameters, swagger_parameter(param.name, "formData", false))
          consumes << "application/x-www-form-urlencoded" unless consumes.includes?("application/x-www-form-urlencoded")
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

      declared_path_params = endpoint.params.compact_map { |p| p.name if p.param_type == "path" }
      oas_path = normalize_oas_path(endpoint.url, declared_path_params)
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
        parameters << {
          "name"        => JSON::Any.new("Cookie"),
          "in"          => JSON::Any.new("header"),
          "type"        => JSON::Any.new("string"),
          "required"    => JSON::Any.new(false),
          "description" => JSON::Any.new(cookie_desc),
        }
      end

      # Add body parameter for JSON content
      # OAS2 does not allow body and formData parameters in the same operation.
      # If both are present, keep the formData shape because it preserves the
      # concrete field names as request parameters.
      if !json_properties.empty? && !has_form
        append_unique_parameter(parameters, {
          "name"     => JSON::Any.new("body"),
          "in"       => JSON::Any.new("body"),
          "required" => JSON::Any.new(false),
          "schema"   => JSON::Any.new({
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new(json_properties),
          } of String => JSON::Any),
        } of String => JSON::Any)
      elsif !json_properties.empty? && has_form
        # OAS2 forbids `body` and `formData` in the same operation, so the
        # JSON body is dropped in favor of the concrete formData fields. Rather
        # than losing the JSON field names entirely, surface each as a query
        # parameter (query + formData are allowed together) so they survive.
        json_properties.each_key do |name|
          append_unique_parameter(parameters, swagger_parameter(name, "query", false))
        end
      end

      if has_form
        consumes.reject! { |content_type| content_type == "application/json" }
      end

      unmapped_path_params = extract_unmapped_path_parameters(parameters, template_names)

      # Build operation object
      operation = {
        "responses" => JSON::Any.new({
          "200" => JSON::Any.new({
            "description" => JSON::Any.new("Successful response"),
          } of String => JSON::Any),
        } of String => JSON::Any),
        "parameters" => JSON::Any.new(parameters.map { |p| JSON::Any.new(p) }),
      } of String => JSON::Any

      # Add consumes if present
      unless consumes.empty?
        operation["consumes"] = JSON::Any.new(consumes.map { |c| JSON::Any.new(c) })
      end

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

    url_parts = swagger_url_parts(@options["url"]?.try(&.to_s) || "")
    oas2_hash = {
      "swagger" => JSON::Any.new("2.0"),
      "info"    => JSON::Any.new({
        "title"   => JSON::Any.new("Generated by Noir"),
        "version" => JSON::Any.new("1.0.0"),
      } of String => JSON::Any),
      "basePath" => JSON::Any.new(url_parts[:base_path]),
      "schemes"  => JSON::Any.new(url_parts[:schemes].map { |scheme| JSON::Any.new(scheme) }),
      "produces" => JSON::Any.new([JSON::Any.new("application/json")]),
      "paths"    => JSON::Any.new(paths.transform_values { |v| JSON::Any.new(v) }),
    } of String => JSON::Any

    if host = url_parts[:host]
      oas2_hash["host"] = JSON::Any.new(host)
    end

    ob_puts JSON::Any.new(oas2_hash).to_pretty_json
  end
end
