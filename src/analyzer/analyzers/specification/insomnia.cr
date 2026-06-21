require "../../../models/analyzer"
require "../../../utils/http_symbols"
require "uri"

module Analyzer::Specification
  class Insomnia < Analyzer
    HTTP_METHODS = ALLOWED_HTTP_METHODS

    def analyze
      locator = CodeLocator.instance

      json_files = locator.all("insomnia-json")
      if json_files.is_a?(Array(String))
        json_files.each do |path|
          next unless File.exists?(path)
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          begin
            process_v4(JSON.parse(content), path)
          rescue e
            @logger.debug "Exception processing #{path}"
            @logger.debug_sub e
          end
        end
      end

      yaml_files = locator.all("insomnia-yaml")
      if yaml_files.is_a?(Array(String))
        yaml_files.each do |path|
          next unless File.exists?(path)
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          begin
            process_v5(YAML.parse(content), path)
          rescue e
            @logger.debug "Exception processing #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    # ------ v4 (JSON) ------

    private def process_v4(json_obj : JSON::Any, source_path : String)
      resources = json_obj["resources"]?
      return unless resources && resources.as_a?
      env = collect_v4_environment(resources.as_a)

      resources.as_a.each do |resource|
        begin
          next unless resource["_type"]?.try(&.as_s?) == "request"
          process_v4_request(resource, env, source_path)
        rescue e
          @logger.debug "Exception processing insomnia v4 resource"
          @logger.debug_sub e
        end
      end
    end

    private def collect_v4_environment(resources : Array(JSON::Any)) : Hash(String, String)
      env = {} of String => String
      resources.each do |resource|
        next unless resource["_type"]?.try(&.as_s?) == "environment"
        if data = resource["data"]?.try(&.as_h?)
          collect_json_env_values(env, data)
        end
      end
      env
    end

    private def process_v4_request(request : JSON::Any, env : Hash(String, String), source_path : String)
      method = (request["method"]?.try(&.as_s?) || "GET").upcase
      return unless HTTP_METHODS.includes?(method)
      url_raw = resolve_vars(request["url"]?.try(&.as_s?) || "", env)
      url_path = extract_path_from_url(url_raw)
      params = [] of Param

      extract_query_param_names(url_raw).each do |name|
        add_param(params, name, "", "query")
      end

      # Query string parameters
      if parameters = request["parameters"]?.try(&.as_a?)
        parameters.each do |p|
          next unless name = p["name"]?.try(&.as_s?)
          next if p["disabled"]?.try(&.as_bool?) == true
          value = p["value"]?.try(&.as_s?) || ""
          add_param(params, name, value, "query")
        end
      end

      # Headers
      if headers = request["headers"]?.try(&.as_a?)
        headers.each do |h|
          next unless name = h["name"]?.try(&.as_s?)
          next if h["disabled"]?.try(&.as_bool?) == true
          next if skipped_header?(name)
          value = h["value"]?.try(&.as_s?) || ""
          add_param(params, name, value, "header")
        end
      end

      # Path variables `:name` placeholders (Insomnia uses `:name` in URLs).
      extract_path_vars(url_path).each do |name|
        add_param(params, name, "", "path")
      end

      if path_parameters = request["pathParameters"]?.try(&.as_a?)
        path_parameters.each do |p|
          next unless name = p["name"]?.try(&.as_s?)
          value = p["value"]?.try(&.as_s?) || ""
          add_param(params, name, value, "path")
        end
      end

      if auth = request["authentication"]?
        process_json_auth(auth, params)
      end

      # Body
      if body = request["body"]?
        process_v4_body(body, params)
      end

      return if url_path.empty?
      @result << Endpoint.new(url_path, method, params, Details.new(PathInfo.new(source_path)))
    end

    private def process_v4_body(body : JSON::Any, params : Array(Param))
      # Older Insomnia exports (formats 2/3) store the request body as a raw
      # string instead of an object. Attempt to parse it as JSON so that body
      # params are still surfaced, and bail out gracefully otherwise.
      if text = body.as_s?
        process_json_body_text(text, params)
        return
      end
      return unless body.as_h?

      mime = (body["mimeType"]?.try(&.as_s?) || "").downcase
      case
      when mime.includes?("application/json")
        if text = body["text"]?.try(&.as_s?)
          process_json_body_text(text, params)
        end
      when mime.includes?("x-www-form-urlencoded"), mime.includes?("multipart/form-data")
        if form_params = body["params"]?.try(&.as_a?)
          form_params.each do |fp|
            next unless name = fp["name"]?.try(&.as_s?)
            next if fp["disabled"]?.try(&.as_bool?) == true
            value = fp["value"]?.try(&.as_s?) || ""
            add_param(params, name, value, "form")
          end
        end
      end
    end

    # ------ v5 (YAML) ------

    private def process_v5(yaml_obj : YAML::Any, source_path : String)
      env = collect_v5_environment(yaml_obj)
      collection = yaml_obj["collection"]?
      return unless collection && collection.as_a?
      walk_v5_items(collection.as_a, env, source_path)
    end

    private def collect_v5_environment(yaml_obj : YAML::Any) : Hash(String, String)
      env = {} of String => String

      # Insomnia v5 exports sometimes embed environments under
      # `environments.data` or as a sibling `environments` block.
      candidates = [] of YAML::Any
      if e = yaml_obj["environments"]?
        candidates << e
      end
      if envs = yaml_obj["environment"]?
        candidates << envs
      end

      candidates.each do |node|
        data = node["data"]? || node
        if h = data.as_h?
          collect_yaml_env_values(env, h)
        end
        if sub_envs = node["subEnvironments"]?.try(&.as_a?)
          sub_envs.each do |sub_env|
            if sub_data = sub_env["data"]?.try(&.as_h?)
              collect_yaml_env_values(env, sub_data)
            end
          end
        end
      end
      env
    end

    private def walk_v5_items(items : Array(YAML::Any), env : Hash(String, String), source_path : String)
      items.each do |item|
        begin
          if children_node = item["children"]?
            if children = children_node.as_a?
              walk_v5_items(children, env, source_path)
              next
            end
          end

          # v5 also stores WebSocket, Socket.IO, gRPC, and MCP nodes with
          # URLs but without HTTP methods. Only HTTP request nodes are
          # endpoints for this analyzer.
          next unless item["url"]?
          next unless method = item["method"]?.try(&.as_s?)
          next unless HTTP_METHODS.includes?(method.upcase)
          process_v5_request(item, env, source_path)
        rescue e
          @logger.debug "Exception processing insomnia v5 item"
          @logger.debug_sub e
        end
      end
    end

    private def process_v5_request(item : YAML::Any, env : Hash(String, String), source_path : String)
      method = (item["method"]?.try(&.as_s?) || "").upcase
      return unless HTTP_METHODS.includes?(method)
      url_raw = resolve_vars(item["url"]?.try(&.as_s?) || "", env)
      url_path = extract_path_from_url(url_raw)
      params = [] of Param

      extract_query_param_names(url_raw).each do |name|
        add_param(params, name, "", "query")
      end

      if parameters_node = item["parameters"]?
        if parameters = parameters_node.as_a?
          parameters.each do |p|
            next unless name = p["name"]?.try(&.as_s?)
            next if p["disabled"]?.try(&.as_bool?) == true
            value = p["value"]?.try(&.as_s?) || ""
            add_param(params, name, value, "query")
          end
        end
      end

      if headers_node = item["headers"]?
        if headers = headers_node.as_a?
          headers.each do |h|
            next unless name = h["name"]?.try(&.as_s?)
            next if h["disabled"]?.try(&.as_bool?) == true
            next if skipped_header?(name)
            value = h["value"]?.try(&.as_s?) || ""
            add_param(params, name, value, "header")
          end
        end
      end

      extract_path_vars(url_path).each do |name|
        add_param(params, name, "", "path")
      end

      if path_parameters_node = item["pathParameters"]?
        if path_parameters = path_parameters_node.as_a?
          path_parameters.each do |p|
            next unless name = p["name"]?.try(&.as_s?)
            value = p["value"]?.try(&.as_s?) || ""
            add_param(params, name, value, "path")
          end
        end
      end

      if auth = item["authentication"]?
        process_yaml_auth(auth, params)
      end

      if body_node = item["body"]?
        process_v5_body(body_node, params)
      end

      return if url_path.empty?
      @result << Endpoint.new(url_path, method, params, Details.new(PathInfo.new(source_path)))
    end

    private def process_v5_body(body : YAML::Any, params : Array(Param))
      # Guard against bodies serialized as scalars rather than mappings.
      if text = body.as_s?
        process_json_body_text(text, params)
        return
      end
      return unless body.as_h?

      mime = (body["mimeType"]?.try(&.as_s?) || "").downcase
      case
      when mime.includes?("application/json")
        if text = body["text"]?.try(&.as_s?)
          process_json_body_text(text, params)
        end
      when mime.includes?("x-www-form-urlencoded"), mime.includes?("multipart/form-data")
        if form_params_node = body["params"]?
          if form_params = form_params_node.as_a?
            form_params.each do |fp|
              next unless name = fp["name"]?.try(&.as_s?)
              next if fp["disabled"]?.try(&.as_bool?) == true
              value = fp["value"]?.try(&.as_s?) || ""
              add_param(params, name, value, "form")
            end
          end
        end
      end
    end

    # ------ shared helpers ------

    # Substitutes Insomnia `{{ var }}` / `{{var}}` / `{{ _.var }}` tokens
    # using the environment map. Unknown tokens are left as-is so the URL
    # parser can still strip them out.
    private def resolve_vars(input : String, env : Hash(String, String)) : String
      return input if input.empty? || env.empty?
      # Iterate so composite variables expand fully. Insomnia commonly defines
      # a base URL as `{{scheme}}://{{host}}{{base_path}}`, so a single pass
      # would leave `{{host}}`/`{{base_path}}` behind and turn them into bogus
      # path segments (e.g. `/:host:base_path/...`).
      resolved = input
      3.times do
        previous = resolved
        resolved = resolved.gsub(/\{\{\s*(?:_\.)?([A-Za-z0-9_.-]+)\s*\}\}/) do |match|
          name = $1
          env.fetch(name, match)
        end
        break if resolved == previous
      end
      resolved
    end

    private def extract_path_from_url(url_string : String) : String
      stripped = url_string.strip
      return "" if stripped.empty?

      if stripped =~ /^https?:\/\//i
        begin
          uri = URI.parse(stripped)
          path = uri.path
          return normalize_path(path.empty? ? "/" : path)
        rescue e
          logger.debug "Failed to parse Insomnia URL '#{stripped}': #{e}"
        end
      elsif stripped =~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//
        return ""
      end

      # No scheme — treat as path-only or host-prefixed.
      without_query = stripped.split("?", 2)[0].split("#", 2)[0]
      path = without_query
      unless path.starts_with?("/")
        if looks_host_prefixed?(path)
          parts = path.split("/", 2)
          return "/" if parts.size == 1
          path = "/" + parts[1]
        else
          path = "/" + path
        end
      end
      normalize_path(path)
    end

    private def extract_query_param_names(url_string : String) : Array(String)
      query = ""
      begin
        uri = URI.parse(url_string)
        query = uri.query || ""
      rescue e
        logger.debug "Failed to parse Insomnia query URL '#{url_string}': #{e}"
      end

      if query.empty?
        idx = url_string.index('?')
        if idx
          query = url_string[(idx + 1)..].split("#", 2)[0]
        end
      end

      names = [] of String
      query.split('&').each do |pair|
        next if pair.empty?
        name = pair.split('=', 2).first.strip
        names << name unless name.empty?
      end
      names
    end

    private def extract_path_vars(path : String) : Array(String)
      vars = [] of String
      path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |m|
        vars << m[1]
      end
      path.scan(/\{([A-Za-z_][A-Za-z0-9_]*)\}/) do |m|
        vars << m[1]
      end
      vars
    end

    private def looks_host_prefixed?(value : String) : Bool
      first = value.split("/", 2).first
      first.includes?(".") || first.includes?(":") || first.downcase == "localhost" || first.includes?("{{")
    end

    private def normalize_path(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized.gsub(/\{\{\s*(?:_\.)?([A-Za-z0-9_.-]+)\s*\}\}/) do
        ":#{normalize_var_name($1)}"
      end
    end

    private def normalize_var_name(name : String) : String
      normalized = name.gsub(/[^A-Za-z0-9_]/, "_")
      normalized = normalized.lstrip('_')
      normalized = normalized.rstrip('_')
      normalized.empty? ? "param" : normalized
    end

    private def add_param(params : Array(Param), name : String, value : String, param_type : String)
      normalized = name.strip
      return if normalized.empty?
      return if params.any? { |p| p.name == normalized && p.param_type == param_type }
      params << Param.new(normalized, value, param_type)
    end

    private def skipped_header?(name : String) : Bool
      normalized = name.strip.downcase
      normalized.empty? || normalized == "content-type" || normalized == "content-length" || normalized == "host"
    end

    private def process_json_body_text(text : String, params : Array(Param))
      parsed = JSON.parse(text)
      if h = parsed.as_h?
        h.each { |k, _| add_param(params, k, "", "json") }
      end
    rescue e
      logger.debug "Failed to parse Insomnia JSON body: #{e}"
    end

    private def process_json_auth(auth : JSON::Any, params : Array(Param))
      return if auth["disabled"]?.try(&.as_bool?) == true
      type = auth["type"]?.try(&.as_s?) || ""
      process_auth_fields(
        type,
        auth["key"]?.try(&.as_s?) || "",
        auth["value"]?.try(&.as_s?) || "",
        auth["addTo"]?.try(&.as_s?) || "",
        auth["token"]?.try(&.as_s?) || "",
        auth["prefix"]?.try(&.as_s?) || "",
        params
      )
    end

    private def process_yaml_auth(auth : YAML::Any, params : Array(Param))
      return if auth["disabled"]?.try(&.as_bool?) == true
      type = auth["type"]?.try(&.as_s?) || ""
      process_auth_fields(
        type,
        auth["key"]?.try(&.as_s?) || "",
        auth["value"]?.try(&.as_s?) || "",
        auth["addTo"]?.try(&.as_s?) || "",
        auth["token"]?.try(&.as_s?) || "",
        auth["prefix"]?.try(&.as_s?) || "",
        params
      )
    end

    private def process_auth_fields(type : String, key : String, value : String, add_to : String, token : String, prefix : String, params : Array(Param))
      case type.downcase
      when "apikey"
        param_type = add_to.downcase.includes?("query") ? "query" : "header"
        add_param(params, key, value, param_type)
      when "bearer"
        auth_prefix = prefix.empty? ? "Bearer" : prefix
        auth_value = token.empty? ? "" : "#{auth_prefix} #{token}"
        add_param(params, "Authorization", auth_value, "header")
      when "basic", "digest", "oauth1", "oauth2", "hawk", "ntlm", "iam", "asap", "singletoken"
        add_param(params, "Authorization", "", "header")
      end
    end

    private def collect_json_env_values(env : Hash(String, String), data : Hash(String, JSON::Any), prefix = "")
      data.each do |k, v|
        key = prefix.empty? ? k : "#{prefix}.#{k}"
        if s = v.as_s?
          env[key] = s
        elsif v.as_i64? || v.as_f? || v.as_bool?
          env[key] = v.to_s
        elsif h = v.as_h?
          collect_json_env_values(env, h, key)
        end
      end
    end

    private def collect_yaml_env_values(env : Hash(String, String), data : Hash(YAML::Any, YAML::Any), prefix = "")
      data.each do |k, v|
        key_part = k.to_s
        key = prefix.empty? ? key_part : "#{prefix}.#{key_part}"
        if s = v.as_s?
          env[key] = s
        elsif v.as_i64? || v.as_f? || v.as_bool?
          env[key] = v.to_s
        elsif h = v.as_h?
          collect_yaml_env_values(env, h, key)
        end
      end
    end
  end
end
