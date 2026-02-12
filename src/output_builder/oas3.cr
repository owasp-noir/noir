require "../models/output_builder"
require "../models/endpoint"
require "uri"
require "json"

class OutputBuilderOas3 < OutputBuilder
  def print(endpoints : Array(Endpoint))
    paths = {} of String => Hash(String, JSON::Any)

    endpoints.each do |endpoint|
      parameters = [] of Hash(String, JSON::Any)
      has_json_body = false
      has_form_body = false
      json_properties = {} of String => JSON::Any
      form_properties = {} of String => JSON::Any

      endpoint.params.each do |param|
        case param.param_type
        when "json"
          # JSON body parameters go into requestBody
          has_json_body = true
          json_properties[param.name] = JSON::Any.new({
            "type" => JSON::Any.new("string"),
          } of String => JSON::Any)
        when "form"
          # Form data parameters go into requestBody
          has_form_body = true
          form_properties[param.name] = JSON::Any.new({
            "type" => JSON::Any.new("string"),
          } of String => JSON::Any)
        when "header"
          # Header parameters
          parameters << {
            "name"     => JSON::Any.new(param.name),
            "in"       => JSON::Any.new("header"),
            "required" => JSON::Any.new(false),
            "schema"   => JSON::Any.new({
              "type" => JSON::Any.new("string"),
            } of String => JSON::Any),
          }
        when "path"
          # Path parameters
          parameters << {
            "name"     => JSON::Any.new(param.name),
            "in"       => JSON::Any.new("path"),
            "required" => JSON::Any.new(true),
            "schema"   => JSON::Any.new({
              "type" => JSON::Any.new("string"),
            } of String => JSON::Any),
          }
        when "cookie"
          # Cookie parameters (supported in OAS3)
          parameters << {
            "name"     => JSON::Any.new(param.name),
            "in"       => JSON::Any.new("cookie"),
            "required" => JSON::Any.new(false),
            "schema"   => JSON::Any.new({
              "type" => JSON::Any.new("string"),
            } of String => JSON::Any),
          }
        else
          # Default to query parameter
          parameters << {
            "name"     => JSON::Any.new(param.name),
            "in"       => JSON::Any.new("query"),
            "required" => JSON::Any.new(false),
            "schema"   => JSON::Any.new({
              "type" => JSON::Any.new("string"),
            } of String => JSON::Any),
          }
        end
      end

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

      # Add requestBody for JSON content
      if has_json_body
        operation["requestBody"] = JSON::Any.new({
          "required" => JSON::Any.new(false),
          "content"  => JSON::Any.new({
            "application/json" => JSON::Any.new({
              "schema" => JSON::Any.new({
                "type"       => JSON::Any.new("object"),
                "properties" => JSON::Any.new(json_properties),
              } of String => JSON::Any),
            } of String => JSON::Any),
          } of String => JSON::Any),
        } of String => JSON::Any)
      elsif has_form_body
        # Add requestBody for form data
        operation["requestBody"] = JSON::Any.new({
          "required" => JSON::Any.new(false),
          "content"  => JSON::Any.new({
            "application/x-www-form-urlencoded" => JSON::Any.new({
              "schema" => JSON::Any.new({
                "type"       => JSON::Any.new("object"),
                "properties" => JSON::Any.new(form_properties),
              } of String => JSON::Any),
            } of String => JSON::Any),
          } of String => JSON::Any),
        } of String => JSON::Any)
      end

      # Convert path parameters from :param to {param} format for OAS3
      uri = URI.parse(endpoint.url)
      oas_path = uri.path.gsub(/:(\w+)/, "{\\1}")
      oas_path = oas_path.gsub(/<[^:>]+:(\w+)>/, "{\\1}") # Handle <type:param> format

      # Initialize path if not exists
      unless paths.has_key?(oas_path)
        paths[oas_path] = {} of String => JSON::Any
      end

      # Add method to path
      paths[oas_path][endpoint.method.downcase] = JSON::Any.new(operation)
    end

    oas3_hash = {
      "openapi" => JSON::Any.new("3.0.3"),
      "info"    => JSON::Any.new({
        "title"   => JSON::Any.new("Generated by Noir"),
        "version" => JSON::Any.new("1.0.0"),
      } of String => JSON::Any),
      "servers" => JSON::Any.new([
        JSON::Any.new({
          "url" => JSON::Any.new(@options["url"].to_s.empty? ? "http://localhost" : @options["url"].to_s),
        } of String => JSON::Any),
      ]),
      "paths" => JSON::Any.new(paths.transform_values { |v| JSON::Any.new(v) }),
    } of String => JSON::Any

    ob_puts JSON::Any.new(oas3_hash).to_pretty_json
  end
end
