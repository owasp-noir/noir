require "../../../models/analyzer"
require "uri"

module Analyzer::Specification
  class Postman < Analyzer
    def analyze
      locator = CodeLocator.instance
      postman_files = locator.all("postman-json")

      if postman_files.is_a?(Array(String))
        postman_files.each do |postman_file|
          if File.exists?(postman_file)
            content = File.read(postman_file, encoding: "utf-8", invalid: :skip)
            json_obj = JSON.parse(content)

            begin
              # Process items (requests) in the collection
              if json_obj["item"]?
                process_items(json_obj["item"], postman_file, collect_variables(json_obj["variable"]?), "", json_obj["auth"]?)
              end
            rescue e
              @logger.debug "Exception processing #{postman_file}"
              @logger.debug_sub e
            end
          end
        end
      end

      @result
    end

    private def process_items(items, source_path : String, variables : Hash(String, String), folder_path = "", inherited_auth : JSON::Any? = nil)
      item_array = items.as_a?
      return unless item_array

      item_array.each do |item|
        begin
          item_variables = merge_variables(variables, item["variable"]?)

          # Check if it's a folder (has nested items) or a request
          if item["item"]?
            # It's a folder, recurse into it. A folder may declare its own auth,
            # which overrides the collection/parent auth for everything beneath it.
            folder_name = item["name"]?.try(&.to_s) || ""
            new_path = folder_path.empty? ? folder_name : "#{folder_path}/#{folder_name}"
            folder_auth = item["auth"]? || inherited_auth
            process_items(item["item"], source_path, item_variables, new_path, folder_auth)
          elsif item["request"]?
            # It's a request, process it
            process_request(item, source_path, item_variables, inherited_auth)
          end
        rescue e
          @logger.debug "Exception processing item"
          @logger.debug_sub e
        end
      end
    end

    private def process_request(item, source_path : String, variables : Hash(String, String), inherited_auth : JSON::Any? = nil)
      request = item["request"]

      if request_url = request.as_s?
        params = [] of Param
        resolved_url = resolve_vars(request_url, variables)
        url_path = extract_path_from_url(resolved_url)
        extract_query_params(resolved_url).each { |param| add_param(params, param) }
        extract_path_vars(url_path).each { |name| add_param(params, Param.new(name, "", "path")) }
        apply_auth(inherited_auth, params)
        @result << Endpoint.new(url_path, "GET", params, Details.new(PathInfo.new(source_path))) unless url_path.empty?
        return
      end

      return unless request.as_h?

      # Get HTTP method
      method = request["method"]?.try(&.as_s?) || "GET"
      method = method.upcase
      method = "GET" if method.empty?

      # Get URL
      url_path = ""
      params = [] of Param

      if request["url"]?
        url_path = process_url(request["url"], variables, params)
      end

      # Extract headers
      if request["header"]?
        request["header"].as_a?.try &.each do |header|
          next if disabled?(header)

          if param_name = header["key"]?.try(&.as_s?)
            param_value = scalar_to_s(header["value"]?) || ""
            # Skip common headers that are not user-controllable
            unless param_name.downcase == "content-type"
              add_param(params, Param.new(param_name, param_value, "header"))
              extract_cookie_params(param_value).each { |param| add_param(params, param) } if param_name.downcase == "cookie"
            end
          end
        end
      end

      # Extract body parameters
      if request["body"]?
        body = request["body"]
        mode = body["mode"]?.try(&.to_s) || ""

        case mode
        when "raw"
          # Try to parse as JSON
          if body["raw"]?
            raw_content = scalar_to_s(body["raw"]?) || ""
            begin
              json_body = JSON.parse(raw_content)
              if json_body.as_h?
                json_body.as_h.each do |key, value|
                  add_param(params, Param.new(key, value.to_s, "json"))
                end
              end
            rescue
              # Not JSON, treat as raw body
            end
          end
        when "urlencoded"
          if body["urlencoded"]?
            body["urlencoded"].as_a?.try &.each do |form_param|
              next if disabled?(form_param)

              if param_name = form_param["key"]?.try(&.as_s?)
                param_value = scalar_to_s(form_param["value"]?) || ""
                add_param(params, Param.new(param_name, param_value, "form"))
              end
            end
          end
        when "formdata"
          if body["formdata"]?
            body["formdata"].as_a?.try &.each do |form_param|
              next if disabled?(form_param)

              if param_name = form_param["key"]?.try(&.as_s?)
                param_value = scalar_to_s(form_param["value"]?) || scalar_to_s(form_param["src"]?) || ""
                add_param(params, Param.new(param_name, param_value, "form"))
              end
            end
          end
        when "graphql"
          if graphql = body["graphql"]?
            if query = scalar_to_s(graphql["query"]?)
              add_param(params, Param.new("query", query, "json"))
            end

            if variables_raw = scalar_to_s(graphql["variables"]?)
              begin
                parsed_variables = JSON.parse(variables_raw)
                if variables_hash = parsed_variables.as_h?
                  variables_hash.each do |key, value|
                    add_param(params, Param.new(key, value.to_s, "json"))
                  end
                end
              rescue
                add_param(params, Param.new("variables", variables_raw, "json"))
              end
            end
          end
        end
      end

      # Authentication. A request-level `auth` block overrides any auth
      # inherited from the enclosing folder/collection.
      apply_auth(request["auth"]? || inherited_auth, params)

      # Create endpoint
      if !url_path.empty?
        @result << Endpoint.new(url_path, method, params, Details.new(PathInfo.new(source_path)))
      end
    rescue e
      @logger.debug "Exception processing request"
      @logger.debug_sub e
    end

    private def process_url(url : JSON::Any, variables : Hash(String, String), params : Array(Param)) : String
      if url_string = url.as_s?
        resolved_url = resolve_vars(url_string, variables)
        extract_query_params(resolved_url).each { |param| add_param(params, param) }
        url_path = extract_path_from_url(resolved_url)
        extract_path_vars(url_path).each { |name| add_param(params, Param.new(name, "", "path")) }
        return url_path
      end

      return "" unless url.as_h?

      raw = resolve_vars(url["raw"]?.try(&.as_s?) || "", variables)
      url_path = ""

      if path_node = url["path"]?
        url_path = extract_path_from_path_node(path_node, variables)
      end
      url_path = extract_path_from_url(raw) if url_path.empty? && !raw.empty?

      if query_array = url["query"]?.try(&.as_a?)
        query_array.each do |query_param|
          next if disabled?(query_param)

          if param_name = query_param["key"]?.try(&.as_s?)
            param_value = scalar_to_s(query_param["value"]?) || ""
            add_param(params, Param.new(param_name, param_value, "query"))
          end
        end
      elsif !raw.empty?
        extract_query_params(raw).each { |param| add_param(params, param) }
      end

      if variable_array = url["variable"]?.try(&.as_a?)
        variable_array.each do |path_var|
          next if disabled?(path_var)

          if param_name = path_var["key"]?.try(&.as_s?)
            param_value = scalar_to_s(path_var["value"]?) || ""
            add_param(params, Param.new(param_name, param_value, "path"))
          end
        end
      end

      extract_path_vars(url_path).each { |name| add_param(params, Param.new(name, "", "path")) }
      url_path
    end

    private def extract_path_from_url(url_string : String) : String
      stripped = url_string.strip
      return "" if stripped.empty?

      begin
        uri = URI.parse(stripped)
        if path = uri.path
          return normalize_path(path) unless path.empty?
        end
      rescue e
        logger.debug "Failed to parse Postman URL '#{stripped}': #{e}"
      end

      if scheme_idx = stripped.index("://")
        rest = stripped[(scheme_idx + 3)..]
        slash_idx = rest.index("/")
        return "/" unless slash_idx

        return normalize_path(rest[slash_idx..])
      end

      pathish = strip_query_and_fragment(stripped)
      return normalize_path(pathish) if pathish.starts_with?("/")

      parts = pathish.split("/", 2)
      first = parts[0]
      if parts.size == 2
        return normalize_path("/#{parts[1]}") if host_like_segment?(first)
        return normalize_path(pathish)
      end

      return "" if unresolved_variable_segment?(first)
      host_like_segment?(first) ? "/" : normalize_path(pathish)
    end

    private def extract_path_from_path_node(path_node : JSON::Any, variables : Hash(String, String)) : String
      if path = path_node.as_s?
        return normalize_path(resolve_vars(path, variables))
      end

      segments = [] of String
      if path_array = path_node.as_a?
        path_array.each do |segment|
          value = scalar_to_s(segment) || segment.to_s
          resolve_vars(value, variables).split("/").each do |part|
            stripped = part.strip
            segments << stripped unless stripped.empty?
          end
        end
      end

      segments.empty? ? "" : normalize_path("/#{segments.join("/")}")
    end

    private def extract_query_params(url_string : String) : Array(Param)
      params = [] of Param
      query_idx = url_string.index("?")
      return params unless query_idx

      fragment_idx = url_string.index("#", query_idx)
      query = fragment_idx ? url_string[(query_idx + 1)...fragment_idx] : url_string[(query_idx + 1)..]
      return params if query.empty?

      begin
        URI::Params.parse(query).each do |key, value|
          params << Param.new(key, value, "query") unless key.empty?
        end
      rescue e
        logger.debug "Failed to parse Postman query params from '#{url_string}': #{e}"
      end
      params
    end

    private def extract_cookie_params(header_value : String) : Array(Param)
      params = [] of Param
      header_value.split(";").each do |part|
        key_value = part.split("=", 2)
        name = key_value[0].strip
        next if name.empty?

        value = key_value.size == 2 ? key_value[1].strip : ""
        params << Param.new(name, value, "cookie")
      end
      params
    end

    private def extract_path_vars(path : String) : Array(String)
      vars = [] of String
      path.scan(/:([A-Za-z_][A-Za-z0-9_.-]*)/) do |m|
        vars << m[1]
      end
      path.scan(/\{([A-Za-z_][A-Za-z0-9_.-]*)\}/) do |m|
        vars << m[1]
      end
      vars.uniq
    end

    private def normalize_path(path : String) : String
      stripped = strip_query_and_fragment(path.strip)
      return "" if stripped.empty?

      # The optional `$` covers Postman dynamic variables such as `{{$guid}}`
      # or `{{$randomInt}}`, which are runtime-generated path segments and
      # should be treated as path parameters rather than left literal.
      normalized = stripped.gsub(/\{\{\s*\$?([A-Za-z0-9_.-]+)\s*\}\}/) do
        ":#{$1.split(".").last}"
      end
      normalized = normalized.gsub(/\{([A-Za-z_][A-Za-z0-9_.-]*)\}/) { ":#{$1}" }
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    private def strip_query_and_fragment(value : String) : String
      end_idx = value.size
      if query_idx = value.index("?")
        end_idx = Math.min(end_idx, query_idx)
      end
      if fragment_idx = value.index("#")
        end_idx = Math.min(end_idx, fragment_idx)
      end
      value[0...end_idx]
    end

    private def host_like_segment?(segment : String) : Bool
      return true if unresolved_variable_segment?(segment)
      downcased = segment.downcase
      downcased == "localhost" || segment.includes?(".") || segment.includes?(":")
    end

    private def unresolved_variable_segment?(segment : String) : Bool
      segment.matches?(/\A\{\{\s*[^}]+\s*\}\}\z/)
    end

    # Surfaces authentication as request parameters so that auth-bearing
    # endpoints are not under-reported. Mirrors the Insomnia analyzer:
    # api keys become header/query params, token-based schemes become an
    # `Authorization` header. `noauth` explicitly clears inherited auth.
    private def apply_auth(auth : JSON::Any?, params : Array(Param))
      return unless auth
      return unless auth.as_h?

      type = (auth["type"]?.try(&.as_s?) || "").downcase
      return if type.empty? || type == "noauth"

      fields = postman_auth_fields(auth, type)
      case type
      when "apikey"
        name = fields["key"]? || ""
        value = fields["value"]? || ""
        location = (fields["in"]? || "header").downcase == "query" ? "query" : "header"
        add_param(params, Param.new(name, value, location))
      when "bearer"
        token = fields["token"]? || ""
        auth_value = token.empty? ? "" : "Bearer #{token}"
        add_param(params, Param.new("Authorization", auth_value, "header"))
      when "basic", "digest", "oauth1", "oauth2", "hawk", "ntlm", "awsv4", "edgegrid", "jwt", "akamai"
        add_param(params, Param.new("Authorization", "", "header"))
      end
    end

    # Postman serializes the auth parameters either as an array of
    # `{key, value}` entries (v2.1) or as a plain object (v2.0). Normalize
    # both into a flat string map.
    private def postman_auth_fields(auth : JSON::Any, type : String) : Hash(String, String)
      fields = {} of String => String
      node = auth[type]?
      return fields unless node

      if entries = node.as_a?
        entries.each do |entry|
          next unless key = entry["key"]?.try(&.as_s?)
          if value = scalar_to_s(entry["value"]?)
            fields[key] = value
          end
        end
      elsif hash = node.as_h?
        hash.each do |key, value|
          if str = scalar_to_s(value)
            fields[key] = str
          end
        end
      end

      fields
    end

    private def collect_variables(node : JSON::Any?) : Hash(String, String)
      variables = {} of String => String
      return variables unless node
      variable_array = node.as_a?
      return variables unless variable_array

      variable_array.each do |variable|
        next if disabled?(variable)

        key = variable["key"]?.try(&.as_s?) || variable["name"]?.try(&.as_s?)
        next unless key

        value = scalar_to_s(variable["value"]?) || scalar_to_s(variable["initialValue"]?)
        variables[key] = value if value
      end

      variables
    end

    private def merge_variables(parent : Hash(String, String), node : JSON::Any?) : Hash(String, String)
      merged = parent.dup
      collect_variables(node).each do |key, value|
        merged[key] = value
      end
      merged
    end

    private def resolve_vars(input : String, variables : Hash(String, String)) : String
      return input if input.empty? || variables.empty?

      resolved = input
      3.times do
        previous = resolved
        resolved = resolved.gsub(/\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/) do |match|
          name = $1
          variables.fetch(name, variables.fetch(name.split(".").last, match))
        end
        break if resolved == previous
      end
      resolved
    end

    private def scalar_to_s(value : JSON::Any?) : String?
      return unless value
      return value.as_s if value.as_s?
      return value.to_s if value.as_i64? || value.as_f? || value.as_bool?
      nil
    end

    private def disabled?(node : JSON::Any) : Bool
      disabled = node["disabled"]?
      return false unless disabled
      disabled.as_bool? == true || disabled.as_s? == "true"
    end

    private def add_param(params : Array(Param), param : Param)
      return if param.name.empty?
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end
  end
end
