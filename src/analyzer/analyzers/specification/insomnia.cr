require "../../../models/analyzer"

module Analyzer::Specification
  class Insomnia < Analyzer
    def analyze
      locator = CodeLocator.instance

      json_files = locator.all("insomnia-json")
      if json_files.is_a?(Array(String))
        json_files.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          begin
            process_v4(JSON.parse(content), details)
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
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          begin
            process_v5(YAML.parse(content), details)
          rescue e
            @logger.debug "Exception processing #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    # ------ v4 (JSON) ------

    private def process_v4(json_obj : JSON::Any, details : Details)
      resources = json_obj["resources"]?
      return unless resources && resources.as_a?
      env = collect_v4_environment(resources.as_a)

      resources.as_a.each do |resource|
        begin
          next unless resource["_type"]?.try(&.as_s?) == "request"
          process_v4_request(resource, env, details)
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
          data.each do |k, v|
            if s = v.as_s?
              env[k] = s
            elsif v.as_i64? || v.as_f? || v.as_bool?
              env[k] = v.to_s
            end
          end
        end
      end
      env
    end

    private def process_v4_request(request : JSON::Any, env : Hash(String, String), details : Details)
      method = (request["method"]?.try(&.as_s?) || "GET").upcase
      url_raw = resolve_vars(request["url"]?.try(&.as_s?) || "", env)
      url_path = extract_path_from_url(url_raw)
      params = [] of Param

      # Query string parameters
      if parameters = request["parameters"]?.try(&.as_a?)
        parameters.each do |p|
          next unless name = p["name"]?.try(&.as_s?)
          next if p["disabled"]?.try(&.as_bool?) == true
          value = p["value"]?.try(&.as_s?) || ""
          params << Param.new(name, value, "query")
        end
      end

      # Headers
      if headers = request["headers"]?.try(&.as_a?)
        headers.each do |h|
          next unless name = h["name"]?.try(&.as_s?)
          next if h["disabled"]?.try(&.as_bool?) == true
          next if name.downcase == "content-type"
          value = h["value"]?.try(&.as_s?) || ""
          params << Param.new(name, value, "header")
        end
      end

      # Path variables `:name` placeholders (Insomnia uses `:name` in URLs).
      extract_path_vars(url_path).each do |name|
        params << Param.new(name, "", "path") unless params.any? { |p| p.name == name && p.param_type == "path" }
      end

      # Body
      if body = request["body"]?
        process_v4_body(body, params)
      end

      return if url_path.empty?
      @result << Endpoint.new(url_path, method, params, details)
    end

    private def process_v4_body(body : JSON::Any, params : Array(Param))
      mime = body["mimeType"]?.try(&.as_s?) || ""
      case
      when mime.includes?("application/json")
        if text = body["text"]?.try(&.as_s?)
          begin
            parsed = JSON.parse(text)
            if h = parsed.as_h?
              h.each { |k, _| params << Param.new(k, "", "json") }
            end
          rescue
          end
        end
      when mime.includes?("x-www-form-urlencoded"), mime.includes?("multipart/form-data")
        if form_params = body["params"]?.try(&.as_a?)
          form_params.each do |fp|
            next unless name = fp["name"]?.try(&.as_s?)
            next if fp["disabled"]?.try(&.as_bool?) == true
            value = fp["value"]?.try(&.as_s?) || ""
            params << Param.new(name, value, "form")
          end
        end
      end
    end

    # ------ v5 (YAML) ------

    private def process_v5(yaml_obj : YAML::Any, details : Details)
      env = collect_v5_environment(yaml_obj)
      collection = yaml_obj["collection"]?
      return unless collection && collection.as_a?
      walk_v5_items(collection.as_a, env, details)
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
          h.each do |k, v|
            key = k.to_s
            if s = v.as_s?
              env[key] = s
            elsif v.as_i64? || v.as_f? || v.as_bool?
              env[key] = v.to_s
            end
          end
        end
      end
      env
    end

    private def walk_v5_items(items : Array(YAML::Any), env : Hash(String, String), details : Details)
      items.each do |item|
        begin
          if children_node = item["children"]?
            if children = children_node.as_a?
              walk_v5_items(children, env, details)
              next
            end
          end

          # Treat any node with a `url` field as a request entry.
          next unless item["url"]?
          process_v5_request(item, env, details)
        rescue e
          @logger.debug "Exception processing insomnia v5 item"
          @logger.debug_sub e
        end
      end
    end

    private def process_v5_request(item : YAML::Any, env : Hash(String, String), details : Details)
      method = (item["method"]?.try(&.as_s?) || "GET").upcase
      url_raw = resolve_vars(item["url"]?.try(&.as_s?) || "", env)
      url_path = extract_path_from_url(url_raw)
      params = [] of Param

      if parameters_node = item["parameters"]?
        if parameters = parameters_node.as_a?
          parameters.each do |p|
            next unless name = p["name"]?.try(&.as_s?)
            next if p["disabled"]?.try(&.as_bool?) == true
            value = p["value"]?.try(&.as_s?) || ""
            params << Param.new(name, value, "query")
          end
        end
      end

      if headers_node = item["headers"]?
        if headers = headers_node.as_a?
          headers.each do |h|
            next unless name = h["name"]?.try(&.as_s?)
            next if h["disabled"]?.try(&.as_bool?) == true
            next if name.downcase == "content-type"
            value = h["value"]?.try(&.as_s?) || ""
            params << Param.new(name, value, "header")
          end
        end
      end

      extract_path_vars(url_path).each do |name|
        params << Param.new(name, "", "path") unless params.any? { |p| p.name == name && p.param_type == "path" }
      end

      if body_node = item["body"]?
        process_v5_body(body_node, params)
      end

      return if url_path.empty?
      @result << Endpoint.new(url_path, method, params, details)
    end

    private def process_v5_body(body : YAML::Any, params : Array(Param))
      mime = body["mimeType"]?.try(&.as_s?) || ""
      case
      when mime.includes?("application/json")
        if text = body["text"]?.try(&.as_s?)
          begin
            parsed = JSON.parse(text)
            if h = parsed.as_h?
              h.each { |k, _| params << Param.new(k, "", "json") }
            end
          rescue
          end
        end
      when mime.includes?("x-www-form-urlencoded"), mime.includes?("multipart/form-data")
        if form_params_node = body["params"]?
          if form_params = form_params_node.as_a?
            form_params.each do |fp|
              next unless name = fp["name"]?.try(&.as_s?)
              next if fp["disabled"]?.try(&.as_bool?) == true
              value = fp["value"]?.try(&.as_s?) || ""
              params << Param.new(name, value, "form")
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
      input.gsub(/\{\{\s*(?:_\.)?([A-Za-z0-9_]+)\s*\}\}/) do |match|
        name = $1
        env.fetch(name, match)
      end
    end

    private def extract_path_from_url(url_string : String) : String
      return "" if url_string.empty?
      begin
        uri = URI.parse(url_string)
        path = uri.path
        return path if path && !path.empty?
      rescue
      end

      # No scheme — treat as path-only or host-prefixed.
      stripped = url_string.sub(/^https?:\/\//, "")
      if stripped.includes?("/")
        return "/" + stripped.split("/", 2)[1].split("?")[0]
      end
      stripped.starts_with?("/") ? stripped : ""
    end

    private def extract_path_vars(path : String) : Array(String)
      vars = [] of String
      path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |m|
        vars << m[1]
      end
      vars
    end
  end
end
