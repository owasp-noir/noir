require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "uri"
require "json"

@[Noir::OutputFormat(name: "postman", description: "Postman collection", order: 160, structured: true)]
class OutputBuilderPostman < OutputBuilder
  def print(endpoints : Array(Endpoint))
    items = [] of Hash(String, JSON::Any)

    endpoints.each do |endpoint|
      # mobile deep links / CLI commands aren't HTTP requests, so a Postman
      # request item (URI.parse + {{baseUrl}} + HTTP verbs) is meaningless
      # for them — keep them out of the collection.
      next if endpoint.non_http?
      # `URI.parse` is used for the authority only — scheme / host / port sit
      # ahead of anything a route pattern can spell, so it reads those
      # correctly. The path, query and fragment come from `split_route_url`,
      # which knows a `?` in a route is as often regex or optional-segment
      # syntax as it is a query separator. Taking them from `URI` truncated
      # Giraffe's `/legacy(/?)` to `/legacy(` and emitted a query parameter
      # named `:a|b)/(.*)?` for Drogon's `/grp/(?:a|b)/(.*)?`.
      uri = URI.parse(endpoint.url)
      url_parts = split_route_url(endpoint.url)

      # Build URL parts
      path_parts = route_path(url_parts[:route]).split("/").reject(&.empty?)
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

      query_pairs = merged_query_pairs(url_parts[:query], endpoint)
      url_obj = build_url_object(uri, path_with_vars, query_pairs)

      # Add path variables
      path_vars = [] of JSON::Any
      endpoint.params.each do |param|
        if param.request_type == "path"
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
        if param.request_type == "header"
          headers << JSON::Any.new({
            "key"   => JSON::Any.new(param.name),
            "value" => JSON::Any.new(param.value),
          } of String => JSON::Any)
        elsif param.request_type == "cookie"
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
      has_json_body = endpoint.params.any? { |p| p.request_type == "json" }
      has_form_body = endpoint.params.any? { |p| p.request_type == "form" }

      if has_json_body
        json_body = {} of String => JSON::Any
        endpoint.params.each do |param|
          if param.request_type == "json"
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
          if param.request_type == "form"
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
          "name"    => JSON::Any.new("#{method} #{item_label(uri, url_parts)}"),
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
          "value" => JSON::Any.new(base_url),
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
  # `[]?`, not `[]`: `config_initializer` seeds every key for CLI runs, but a
  # builder constructed with a partial options hash (specs, library use) hit a
  # KeyError here while the oas2 builder read the same option safely.
  private def base_url : String
    url = @options["url"]?.to_s
    url.empty? ? "http://localhost" : url
  end

  # The query string the emitted request actually carries: the one the route
  # itself spells out, plus the query params the analyzer recorded.
  #
  # This builder is the only one that *reconstructs* the URL (`URI.parse` then
  # `uri.path`) instead of passing `endpoint.url` through, so `uri.query` was
  # dropped on the floor. `raw` was rebuilt from the path alone and the
  # structured `query` list only ever came from declared params, so a route
  # addressed through its query — `admin-ajax.php?action=get_user_data`, which
  # is how WordPress reaches an AJAX handler — imported as a request that hits
  # a different handler entirely. curl, httpie, powershell and only-url all
  # keep it because they never take the URL apart.
  #
  # Merge order mirrors `bake_endpoint`: a pair the route already spells
  # verbatim is not repeated, while a *different* value for the same name is
  # appended as an override (the later pair is the one servers read).
  private def merged_query_pairs(route_query : Array(Tuple(String, String)), endpoint : Endpoint) : Array(Tuple(String, String))
    pairs = route_query.dup

    endpoint.params.each do |param|
      next unless param.request_type == "query"
      next if pairs.includes?({param.name, param.value})
      # A value-less declaration of a name the route already pins is the same
      # parameter, not an override: appending `action=` after
      # `action=save_settings` blanks out the value that reaches the handler.
      next if param.value.empty? && pairs.any? { |name, _| name == param.name }

      pairs << {param.name, param.value}
    end

    pairs
  end

  private def build_url_object(uri : URI, path_with_vars : Array(String),
                               query_pairs : Array(Tuple(String, String))) : Hash(String, JSON::Any)
    host = uri.host
    if host.nil? || host.empty?
      url_obj = {
        "raw"  => JSON::Any.new(with_query("{{baseUrl}}/#{path_with_vars.join("/")}", query_pairs)),
        "host" => JSON::Any.new([JSON::Any.new("{{baseUrl}}")]),
        "path" => JSON::Any.new(path_with_vars.map { |p| JSON::Any.new(p) }),
      } of String => JSON::Any
      add_query_list(url_obj, query_pairs)
      return url_obj
    end

    authority = String.build do |io|
      io << uri.scheme << "://" if uri.scheme
      io << host
      io << ':' << uri.port if uri.port
    end

    url_obj = {
      # Postman splits a real host into its domain labels.
      "raw"  => JSON::Any.new(with_query("#{authority}/#{path_with_vars.join("/")}", query_pairs)),
      "host" => JSON::Any.new(host.split('.').map { |label| JSON::Any.new(label) }),
      "path" => JSON::Any.new(path_with_vars.map { |p| JSON::Any.new(p) }),
    } of String => JSON::Any

    if scheme = uri.scheme
      url_obj["protocol"] = JSON::Any.new(scheme)
    end
    if port = uri.port
      url_obj["port"] = JSON::Any.new(port.to_s)
    end

    add_query_list(url_obj, query_pairs)
    url_obj
  end

  # `raw` is the field a human reads in the URL bar and the one most
  # non-Postman importers key off, so it has to agree with the structured
  # `query` list built from the same pairs.
  private def with_query(raw : String, query_pairs : Array(Tuple(String, String))) : String
    return raw if query_pairs.empty?

    "#{raw}?#{query_pairs.map { |name, value| "#{name}=#{value}" }.join("&")}"
  end

  private def add_query_list(url_obj : Hash(String, JSON::Any), query_pairs : Array(Tuple(String, String)))
    return if query_pairs.empty?

    url_obj["query"] = JSON::Any.new(query_pairs.map do |name, value|
      JSON::Any.new({
        "key"   => JSON::Any.new(name),
        "value" => JSON::Any.new(value),
      } of String => JSON::Any)
    end)
  end

  # The sidebar shows this name alone, so it has to carry every part of the URL
  # that distinguishes one entry from another: the host (an absolute
  # `demo.example.com/api/users/{id}` and `demo.example.com.evil/api/users/{id}`
  # otherwise read identically) and the route's own query string — the only
  # thing telling `admin-ajax.php?action=get_user_data` from
  # `?action=save_settings`, which is 8 endpoints under 4 names on the
  # WordPress fixture.
  #
  # It also has to carry the `#fragment` Noir uses to address many operations
  # on one path: every GraphQL resolver and JSON-RPC method lives at the same
  # `POST /graphql`, so without it Hasura's 15 operations were 15 sidebar
  # entries all reading `POST /v1/graphql`, with nothing saying which was
  # which. The fragment stays out of the request URL — it is Noir's
  # discriminator, not something a server ever sees — so only the name
  # carries it.
  #
  # Deliberately the route's own query and not the merged pairs
  # `build_url_object` uses: an inline query is part of how the route is
  # addressed, while a declared query param is an input *to* a route and
  # doesn't change its identity. Folding declared params in here would rename
  # every parameterised endpoint.
  private def item_label(uri : URI, url_parts) : String
    host = uri.host
    path = route_path(url_parts[:route])
    label = host.nil? || host.empty? ? path : "#{host}#{path}"

    query = url_parts[:query]
    unless query.empty?
      label = "#{label}?#{query.map { |name, value| "#{name}=#{value}" }.join("&")}"
    end

    fragment = url_parts[:fragment]
    fragment ? "#{label}##{fragment}" : label
  end
end
