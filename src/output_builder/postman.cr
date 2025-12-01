require "../models/output_builder"
require "../models/endpoint"
require "uri"
require "json"

class OutputBuilderPostman < OutputBuilder
  def print(endpoints : Array(Endpoint))
    items = [] of Hash(String, JSON::Any)

    endpoints.each do |endpoint|
      uri = URI.parse(endpoint.url)

      # Build URL parts
      path_parts = uri.path.split("/").reject(&.empty?)
      path_with_vars = path_parts.map do |part|
        if part.starts_with?("<") && part.ends_with?(">") && part.includes?(":")
          # Handle <type:param> format - convert to :param
          match = part.match(/<[^:>]+:(\w+)>/)
          match ? ":#{match[1]}" : part
        else
          part
        end
      end

      # Build URL object
      url_obj = {
        "raw"  => JSON::Any.new("{{baseUrl}}/#{path_with_vars.join("/")}"),
        "host" => JSON::Any.new([JSON::Any.new("{{baseUrl}}")]),
        "path" => JSON::Any.new(path_with_vars.map { |p| JSON::Any.new(p) }),
      } of String => JSON::Any

      # Add query parameters
      query_params = [] of JSON::Any
      endpoint.params.each do |param|
        if param.param_type == "query"
          query_params << JSON::Any.new({
            "key"   => JSON::Any.new(param.name),
            "value" => JSON::Any.new(param.value),
          } of String => JSON::Any)
        end
      end

      if !query_params.empty?
        url_obj["query"] = JSON::Any.new(query_params)
      end

      # Add path variables
      path_vars = [] of JSON::Any
      endpoint.params.each do |param|
        if param.param_type == "path"
          path_vars << JSON::Any.new({
            "key"   => JSON::Any.new(param.name),
            "value" => JSON::Any.new(param.value),
          } of String => JSON::Any)
        end
      end

      if !path_vars.empty?
        url_obj["variable"] = JSON::Any.new(path_vars)
      end

      # Build headers
      headers = [] of JSON::Any
      endpoint.params.each do |param|
        if param.param_type == "header"
          headers << JSON::Any.new({
            "key"   => JSON::Any.new(param.name),
            "value" => JSON::Any.new(param.value),
          } of String => JSON::Any)
        elsif param.param_type == "cookie"
          # Find existing Cookie header or create new one
          existing_cookie = headers.find { |h| h["key"].as_s == "Cookie" }
          if existing_cookie
            # Append to existing cookie value
            current_val = existing_cookie["value"].as_s
            # We need to rebuild since JSON::Any is immutable
            headers.reject! { |h| h["key"].as_s == "Cookie" }
            headers << JSON::Any.new({
              "key"   => JSON::Any.new("Cookie"),
              "value" => JSON::Any.new("#{current_val}; #{param.name}=#{param.value}"),
            } of String => JSON::Any)
          else
            headers << JSON::Any.new({
              "key"   => JSON::Any.new("Cookie"),
              "value" => JSON::Any.new("#{param.name}=#{param.value}"),
            } of String => JSON::Any)
          end
        end
      end

      # Build request body
      body = nil
      has_json_body = endpoint.params.any? { |p| p.param_type == "json" }
      has_form_body = endpoint.params.any? { |p| p.param_type == "form" }

      if has_json_body
        json_body = {} of String => JSON::Any
        endpoint.params.each do |param|
          if param.param_type == "json"
            json_body[param.name] = JSON::Any.new(param.value)
          end
        end

        body = {
          "mode" => JSON::Any.new("raw"),
          "raw"  => JSON::Any.new(json_body.to_json),
          "options" => JSON::Any.new({
            "raw" => JSON::Any.new({
              "language" => JSON::Any.new("json"),
            } of String => JSON::Any),
          } of String => JSON::Any),
        } of String => JSON::Any

        # Add Content-Type header if not already present
        unless headers.any? { |h| h["key"].as_s.downcase == "content-type" }
          headers << JSON::Any.new({
            "key"   => JSON::Any.new("Content-Type"),
            "value" => JSON::Any.new("application/json"),
          } of String => JSON::Any)
        end
      elsif has_form_body
        form_data = [] of JSON::Any
        endpoint.params.each do |param|
          if param.param_type == "form"
            form_data << JSON::Any.new({
              "key"   => JSON::Any.new(param.name),
              "value" => JSON::Any.new(param.value),
              "type"  => JSON::Any.new("text"),
            } of String => JSON::Any)
          end
        end

        body = {
          "mode"       => JSON::Any.new("urlencoded"),
          "urlencoded" => JSON::Any.new(form_data),
        } of String => JSON::Any
      end

      # Build request object
      request = {
        "method" => JSON::Any.new(endpoint.method),
        "header" => JSON::Any.new(headers),
        "url"    => JSON::Any.new(url_obj),
      } of String => JSON::Any

      if body
        request["body"] = JSON::Any.new(body)
      end

      # Build item
      item = {
        "name"    => JSON::Any.new("#{endpoint.method} #{uri.path}"),
        "request" => JSON::Any.new(request),
      } of String => JSON::Any

      items << item
    end

    # Build collection
    collection = {
      "info" => JSON::Any.new({
        "name"   => JSON::Any.new("Generated by Noir"),
        "schema" => JSON::Any.new("https://schema.getpostman.com/json/collection/v2.1.0/collection.json"),
      } of String => JSON::Any),
      "item" => JSON::Any.new(items.map { |i| JSON::Any.new(i) }),
      "variable" => JSON::Any.new([
        JSON::Any.new({
          "key"   => JSON::Any.new("baseUrl"),
          "value" => JSON::Any.new(@options["url"].to_s.empty? ? "http://localhost" : @options["url"].to_s),
        } of String => JSON::Any),
      ]),
    } of String => JSON::Any

    ob_puts JSON::Any.new(collection).to_pretty_json
  end
end
