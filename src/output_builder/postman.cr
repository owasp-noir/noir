require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "uri"
require "json"

class OutputBuilderPostman < OutputBuilder
  def print(endpoints : Array(Endpoint))
    items = [] of Hash(String, JSON::Any)

    endpoints.each do |endpoint|
      # mobile deep links / CLI commands aren't HTTP requests, so a Postman
      # request item (URI.parse + {{baseUrl}} + HTTP verbs) is meaningless
      # for them — keep them out of the collection.
      next if endpoint.non_http?
      uri = URI.parse(endpoint.url)

      # Build URL parts
      path_parts = uri.path.split("/").reject(&.empty?)
      path_with_vars = path_parts.map do |part|
        if part.starts_with?("<") && part.ends_with?(">") && part.includes?(":")
          # Handle <type:param> format - convert to :param
          match = part.match(/<[^:>]+:(\w+)>/)
          match ? ":#{match[1]}" : part
        elsif part.starts_with?("{") && part.ends_with?("}")
          # Handle {name} / {name:constraint} - convert to Postman's :name so the
          # `variable` entry actually links to the URL placeholder.
          match = part.match(/\A\{(\w+)(?::[^}]+)?\}\z/)
          match ? ":#{match[1]}" : part
        else
          part
        end
      end

      url_obj = build_url_object(uri, path_with_vars)

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
        # `raw` is the field a human reads in the URL bar and the one most
        # non-Postman importers key off, so it has to agree with the
        # structured `query` list. It was built from the path alone, which
        # also dropped a query string the route itself carried
        # (`admin-ajax.php?action=…`).
        url_obj["raw"] = JSON::Any.new(raw_with_query(url_obj["raw"].as_s, query_params))
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
          # Find existing Cookie header or create new one. Header names are
          # case-insensitive (RFC 7230), so match `cookie`/`COOKIE` too —
          # otherwise a header-type param named `cookie` and the cookie-type
          # Cookie header would both be emitted. (Mirrors the Content-Type
          # case-insensitive match elsewhere in this builder.)
          existing_cookie = headers.find { |h| h["key"].as_s.downcase == "cookie" }
          if existing_cookie
            # Append to existing cookie value
            current_val = existing_cookie["value"].as_s
            # We need to rebuild since JSON::Any is immutable
            headers.reject! { |h| h["key"].as_s.downcase == "cookie" }
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
          "mode"    => JSON::Any.new("raw"),
          "raw"     => JSON::Any.new(json_body.to_json),
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

      expand_synthetic_http_methods(endpoint.method).each do |method|
        # Build request object
        request = {
          "method" => JSON::Any.new(method),
          "header" => JSON::Any.new(headers),
          "url"    => JSON::Any.new(url_obj),
        } of String => JSON::Any

        if body
          request["body"] = JSON::Any.new(body)
        end

        # Build item. The host is part of the name for an absolute URL:
        # without it `demo.example.com/api/users/{id}` and
        # `demo.example.com.evil/api/users/{id}` are two entries in the
        # sidebar reading exactly the same.
        item = {
          "name"    => JSON::Any.new("#{method} #{item_label(uri)}"),
          "request" => JSON::Any.new(request),
        } of String => JSON::Any

        if description = noir_ai_context_description(endpoint) || noir_callees_description(endpoint)
          item["description"] = JSON::Any.new(description)
        end

        items << item
      end
    end

    # Build collection
    collection = {
      "info" => JSON::Any.new({
        "name"   => JSON::Any.new("Generated by Noir"),
        "schema" => JSON::Any.new("https://schema.getpostman.com/json/collection/v2.1.0/collection.json"),
      } of String => JSON::Any),
      "item"     => JSON::Any.new(items.map { |i| JSON::Any.new(i) }),
      "variable" => JSON::Any.new([
        JSON::Any.new({
          "key"   => JSON::Any.new("baseUrl"),
          "value" => JSON::Any.new(@options["url"].to_s.empty? ? "http://localhost" : @options["url"].to_s),
        } of String => JSON::Any),
      ]),
    } of String => JSON::Any

    ob_puts JSON::Any.new(collection).to_pretty_json
  end

  # Postman addresses a request either through the collection's `baseUrl`
  # variable — the common case, an endpoint discovered as a bare path — or
  # through its own absolute URL. Spec- and capture-derived endpoints carry a
  # real host (an OpenAPI `servers` entry, a HAR capture spanning domains),
  # and rewriting those to `{{baseUrl}}` aimed every request at one host,
  # throwing away the host Noir had actually found: `demo.example.com` and
  # `demo.example.com.evil` imported as the same request. curl, httpie and
  # only-url all keep the host on the same scan; this now does too.
  private def build_url_object(uri : URI, path_with_vars : Array(String)) : Hash(String, JSON::Any)
    host = uri.host
    if host.nil? || host.empty?
      return {
        "raw"  => JSON::Any.new("{{baseUrl}}/#{path_with_vars.join("/")}"),
        "host" => JSON::Any.new([JSON::Any.new("{{baseUrl}}")]),
        "path" => JSON::Any.new(path_with_vars.map { |p| JSON::Any.new(p) }),
      } of String => JSON::Any
    end

    authority = String.build do |io|
      io << uri.scheme << "://" if uri.scheme
      io << host
      io << ':' << uri.port if uri.port
    end

    url_obj = {
      # Postman splits a real host into its domain labels.
      "raw"  => JSON::Any.new("#{authority}/#{path_with_vars.join("/")}"),
      "host" => JSON::Any.new(host.split('.').map { |label| JSON::Any.new(label) }),
      "path" => JSON::Any.new(path_with_vars.map { |p| JSON::Any.new(p) }),
    } of String => JSON::Any

    if scheme = uri.scheme
      url_obj["protocol"] = JSON::Any.new(scheme)
    end
    if port = uri.port
      url_obj["port"] = JSON::Any.new(port.to_s)
    end

    url_obj
  end

  private def raw_with_query(raw : String, query_params : Array(JSON::Any)) : String
    pairs = query_params.map do |param|
      entry = param.as_h
      "#{entry["key"].as_s}=#{entry["value"].as_s}"
    end

    "#{raw}#{raw.includes?('?') ? '&' : '?'}#{pairs.join("&")}"
  end

  private def item_label(uri : URI) : String
    host = uri.host
    return uri.path if host.nil? || host.empty?

    "#{host}#{uri.path}"
  end
end
