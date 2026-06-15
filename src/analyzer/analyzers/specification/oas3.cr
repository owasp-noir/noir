require "../../../models/analyzer"
require "../../../utils/yaml"
require "uri"

module Analyzer::Specification
  class Oas3 < Analyzer
    HTTP_METHODS = {"get", "post", "put", "delete", "patch", "options", "head", "trace"}

    def get_base_path(servers : JSON::Any)
      server_base_path(servers.as_a.map { |server_obj| server_url_json(server_obj) })
    end

    def get_base_path(servers : YAML::Any)
      server_base_path(servers.as_a.map { |server_obj| server_url_yaml(server_obj) })
    end

    # Maps an OAS3 request-body content type to a Noir param type.
    private def param_type_for_content(content_type : String) : String?
      media_type = content_type.split(';', 2).first.strip.downcase
      case media_type
      when "application/json"
        "json"
      when "application/x-www-form-urlencoded"
        "form"
      when .starts_with?("multipart/form-data")
        "form"
      else
        if media_type.ends_with?("+json")
          "json"
        end
      end
    end

    # Resolves `#/components/schemas/Name` etc. against the spec root.
    private def resolve_ref_json(root : JSON::Any, ref : String) : JSON::Any?
      return unless ref.starts_with?("#/")
      node = root
      ref[2..].split('/').each do |segment|
        decoded = segment.gsub("~1", "/").gsub("~0", "~")
        return unless hash = node.as_h?
        return unless next_node = hash[decoded]?
        node = next_node
      end
      node
    end

    private def resolve_ref_yaml(root : YAML::Any, ref : String) : YAML::Any?
      return unless ref.starts_with?("#/")
      node = root
      ref[2..].split('/').each do |segment|
        decoded = segment.gsub("~1", "/").gsub("~0", "~")
        return unless hash = node.as_h?
        return unless next_node = hash[YAML::Any.new(decoded)]?
        node = next_node
      end
      node
    end

    private def add_param(params : Array(Param), name : String, param_type : String)
      return if name.empty?
      param = Param.new(name, "", param_type)
      params << param unless params.includes?(param)
    end

    private def server_url_json(server_obj : JSON::Any) : String
      url = server_obj["url"]?.try(&.as_s?) || ""
      if variables = server_obj["variables"]?.try(&.as_h?)
        variables.each do |name, variable_obj|
          default = variable_obj["default"]?.try(&.as_s?)
          url = url.gsub("{#{name}}", default) if default
        end
      end
      url
    end

    private def server_url_yaml(server_obj : YAML::Any) : String
      url = server_obj[YAML::Any.new("url")]?.try(&.as_s?) || ""
      if variables_node = server_obj[YAML::Any.new("variables")]?
        if variables = variables_node.as_h?
          variables.each do |name, variable_obj|
            default = variable_obj[YAML::Any.new("default")]?.try(&.as_s?)
            url = url.gsub("{#{name}}", default) if default
          end
        end
      end
      url
    end

    private def server_base_path(server_urls : Array(String)) : String
      server_urls.each do |server_url|
        next if server_url.empty?

        if server_url.starts_with?("http")
          next if @url.empty?
          user_uri = URI.parse(@url)
          source_uri = URI.parse(server_url)
          return combine_base_url(source_uri.path) if user_uri.host == source_uri.host
        elsif server_url.starts_with?("/")
          return combine_base_url(server_url)
        else
          return combine_base_url("/#{server_url}")
        end
      rescue
        next
      end

      @url
    end

    private def combine_base_url(path : String) : String
      return @url if path.empty?
      return path if @url.empty?
      if @url.ends_with?("/") && path.starts_with?("/")
        @url + path[1..]
      elsif !@url.ends_with?("/") && !path.starts_with?("/")
        "#{@url}/#{path}"
      else
        @url + path
      end
    end

    # Walks an OAS3 schema, emitting one Param per top-level property.
    # Follows `$ref` and flattens `allOf` so referenced/composed schemas
    # surface their members.
    private def collect_schema_props_json(root : JSON::Any, schema : JSON::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # JSON Schema allows boolean `items` etc.; a scalar node makes the
      # `["..."]?` subscripts below raise "Expected Hash".
      return unless schema.as_h?
      if ref = schema["$ref"]?.try(&.as_s?)
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          collect_schema_props_json(root, resolved, param_type, params, seen)
        end
        return
      end

      if items = schema["items"]?
        collect_schema_props_json(root, items, param_type, params, seen)
      end

      if props = schema["properties"]?.try(&.as_h?)
        props.each do |name, _|
          add_param(params, name.to_s, param_type)
        end
      end

      if all_of = schema["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_schema_props_json(root, s, param_type, params, seen) }
      end

      if one_of = schema["oneOf"]?.try(&.as_a?)
        one_of.each { |s| collect_schema_props_json(root, s, param_type, params, seen) }
      end

      if any_of = schema["anyOf"]?.try(&.as_a?)
        any_of.each { |s| collect_schema_props_json(root, s, param_type, params, seen) }
      end
    end

    private def collect_schema_props_yaml(root : YAML::Any, schema : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # JSON Schema allows boolean `items` etc.; a scalar node makes the
      # `[...]?` subscripts below raise "Expected Hash".
      return unless schema.as_h?
      if ref_node = schema[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return if seen.includes?(ref)
          seen << ref
          if resolved = resolve_ref_yaml(root, ref)
            collect_schema_props_yaml(root, resolved, param_type, params, seen)
          end
        end
        return
      end

      if items_node = schema[YAML::Any.new("items")]?
        collect_schema_props_yaml(root, items_node, param_type, params, seen)
      end

      if props_node = schema[YAML::Any.new("properties")]?
        if props = props_node.as_h?
          props.each do |name, _|
            add_param(params, name.to_s, param_type)
          end
        end
      end

      if all_of_node = schema[YAML::Any.new("allOf")]?
        if all_of = all_of_node.as_a?
          all_of.each { |s| collect_schema_props_yaml(root, s, param_type, params, seen) }
        end
      end

      if one_of_node = schema[YAML::Any.new("oneOf")]?
        if one_of = one_of_node.as_a?
          one_of.each { |s| collect_schema_props_yaml(root, s, param_type, params, seen) }
        end
      end

      if any_of_node = schema[YAML::Any.new("anyOf")]?
        if any_of = any_of_node.as_a?
          any_of.each { |s| collect_schema_props_yaml(root, s, param_type, params, seen) }
        end
      end
    end

    private def extract_param_json(root : JSON::Any, param_obj : JSON::Any, params : Array(Param))
      if ref = param_obj["$ref"]?.try(&.as_s?)
        if resolved = resolve_ref_json(root, ref)
          extract_param_json(root, resolved, params)
        end
        return
      end

      name = param_obj["name"]?.try(&.to_s) || ""
      location = param_obj["in"]?.try(&.to_s) || ""
      return if name.empty?
      case location
      when "query"
        add_param(params, name, "query")
      when "header"
        add_param(params, name, "header")
      when "cookie"
        add_param(params, name, "cookie")
      end
    end

    private def extract_param_yaml(root : YAML::Any, param_obj : YAML::Any, params : Array(Param))
      if ref_node = param_obj[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          if resolved = resolve_ref_yaml(root, ref)
            extract_param_yaml(root, resolved, params)
          end
        end
        return
      end

      name = param_obj[YAML::Any.new("name")]?.try(&.to_s) || ""
      location = param_obj[YAML::Any.new("in")]?.try(&.to_s) || ""
      return if name.empty?
      case location
      when "query"
        add_param(params, name, "query")
      when "header"
        add_param(params, name, "header")
      when "cookie"
        add_param(params, name, "cookie")
      end
    end

    # Builds `scheme name => Param` from `components.securitySchemes`. An
    # `apiKey` scheme is a concrete request parameter (header/query/cookie);
    # token schemes (`http` bearer/basic, `oauth2`, `openIdConnect`) ride on the
    # `Authorization` header. This mirrors how the Insomnia analyzer turns auth
    # config into params, so a documented requirement isn't a false negative.
    private def security_schemes_json(root : JSON::Any) : Hash(String, Param)
      result = {} of String => Param
      return result unless components = root["components"]?.try(&.as_h?)
      return result unless schemes = components["securitySchemes"]?.try(&.as_h?)
      schemes.each do |name, obj|
        if param = security_scheme_param_json(root, obj)
          result[name.to_s] = param
        end
      end
      result
    end

    private def security_scheme_param_json(root : JSON::Any, obj : JSON::Any, seen : Set(String) = Set(String).new) : Param?
      return unless obj_h = obj.as_h?
      if ref = obj_h["$ref"]?.try(&.as_s?)
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          return security_scheme_param_json(root, resolved, seen)
        end
        return
      end

      case obj_h["type"]?.try(&.as_s?).try(&.downcase)
      when "apikey"
        name = obj_h["name"]?.try(&.as_s?) || ""
        return if name.empty?
        case obj_h["in"]?.try(&.as_s?)
        when "header" then Param.new(name, "", "header")
        when "query"  then Param.new(name, "", "query")
        when "cookie" then Param.new(name, "", "cookie")
        end
      when "http", "oauth2", "openidconnect"
        Param.new("Authorization", "", "header")
      end
    end

    # Adds params for the effective security requirement. Per the OAS spec an
    # operation-level `security` (including an empty `[]` that opts out) wins
    # over the global default; otherwise the global default applies.
    private def apply_security_json(effective : JSON::Any?, schemes : Hash(String, Param), params : Array(Param))
      return if schemes.empty?
      return unless effective
      return unless requirements = effective.as_a?
      requirements.each do |requirement|
        next unless requirement_h = requirement.as_h?
        requirement_h.each_key do |scheme_name|
          if param = schemes[scheme_name.to_s]?
            params << param unless params.includes?(param)
          end
        end
      end
    end

    private def security_schemes_yaml(root : YAML::Any) : Hash(String, Param)
      result = {} of String => Param
      return result unless components = root[YAML::Any.new("components")]?.try(&.as_h?)
      return result unless schemes = components[YAML::Any.new("securitySchemes")]?.try(&.as_h?)
      schemes.each do |name, obj|
        if param = security_scheme_param_yaml(root, obj)
          result[name.to_s] = param
        end
      end
      result
    end

    private def security_scheme_param_yaml(root : YAML::Any, obj : YAML::Any, seen : Set(String) = Set(String).new) : Param?
      return unless obj_h = obj.as_h?
      if ref_node = obj_h[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return if seen.includes?(ref)
          seen << ref
          if resolved = resolve_ref_yaml(root, ref)
            return security_scheme_param_yaml(root, resolved, seen)
          end
        end
        return
      end

      case obj_h[YAML::Any.new("type")]?.try(&.as_s?).try(&.downcase)
      when "apikey"
        name = obj_h[YAML::Any.new("name")]?.try(&.as_s?) || ""
        return if name.empty?
        case obj_h[YAML::Any.new("in")]?.try(&.as_s?)
        when "header" then Param.new(name, "", "header")
        when "query"  then Param.new(name, "", "query")
        when "cookie" then Param.new(name, "", "cookie")
        end
      when "http", "oauth2", "openidconnect"
        Param.new("Authorization", "", "header")
      end
    end

    private def apply_security_yaml(effective : YAML::Any?, schemes : Hash(String, Param), params : Array(Param))
      return if schemes.empty?
      return unless effective
      return unless requirements = effective.as_a?
      requirements.each do |requirement|
        next unless requirement_h = requirement.as_h?
        requirement_h.each_key do |scheme_name|
          if param = schemes[scheme_name.to_s]?
            params << param unless params.includes?(param)
          end
        end
      end
    end

    private def resolve_path_item_json(root : JSON::Any, path_obj : JSON::Any, seen : Set(String) = Set(String).new) : JSON::Any
      return path_obj unless path_obj_h = path_obj.as_h?
      return path_obj unless ref = path_obj_h["$ref"]?.try(&.as_s?)
      return path_obj if seen.includes?(ref)
      seen << ref
      resolved = resolve_ref_json(root, ref)
      resolved ? resolve_path_item_json(root, resolved, seen) : path_obj
    end

    private def resolve_path_item_yaml(root : YAML::Any, path_obj : YAML::Any, seen : Set(String) = Set(String).new) : YAML::Any
      return path_obj unless path_obj_h = path_obj.as_h?
      return path_obj unless ref_node = path_obj_h[YAML::Any.new("$ref")]?
      return path_obj unless ref = ref_node.as_s?
      return path_obj if seen.includes?(ref)
      seen << ref
      resolved = resolve_ref_yaml(root, ref)
      resolved ? resolve_path_item_yaml(root, resolved, seen) : path_obj
    end

    private def extract_request_body_json(root : JSON::Any, request_body : JSON::Any, params : Array(Param))
      # The requestBody object itself can be $ref'd to components.requestBodies.
      if ref = request_body["$ref"]?.try(&.as_s?)
        if resolved = resolve_ref_json(root, ref)
          extract_request_body_json(root, resolved, params)
        end
        return
      end
      return unless content = request_body["content"]?.try(&.as_h?)
      content.each do |content_type, content_obj|
        next unless param_type = param_type_for_content(content_type.to_s)
        if schema = content_obj["schema"]?
          collect_schema_props_json(root, schema, param_type, params)
        end
      end
    end

    private def extract_request_body_yaml(root : YAML::Any, request_body : YAML::Any, params : Array(Param))
      if ref_node = request_body[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          if resolved = resolve_ref_yaml(root, ref)
            extract_request_body_yaml(root, resolved, params)
          end
        end
        return
      end
      return unless content_node = request_body[YAML::Any.new("content")]?
      return unless content = content_node.as_h?
      content.each do |content_type, content_obj|
        next unless param_type = param_type_for_content(content_type.to_s)
        if schema_node = content_obj[YAML::Any.new("schema")]?
          collect_schema_props_yaml(root, schema_node, param_type, params)
        end
      end
    end

    def analyze
      locator = CodeLocator.instance
      oas3_jsons = locator.all("oas3-json")
      oas3_yamls = locator.all("oas3-yaml")

      if oas3_jsons.is_a?(Array(String))
        oas3_jsons.each do |oas3_json|
          if File.exists?(oas3_json)
            details = Details.new(PathInfo.new(oas3_json))
            content = File.read(oas3_json, encoding: "utf-8", invalid: :skip)
            json_obj = JSON.parse(content)

            base_path = @url
            begin
              base_path = get_base_path json_obj["servers"]
            rescue e
              @logger.debug "Exception of #{oas3_json}/servers"
              @logger.debug_sub e
            end

            process_paths_json(json_obj, base_path, details, oas3_json)
          end
        end
      end

      if oas3_yamls.is_a?(Array(String))
        oas3_yamls.each do |oas3_yaml|
          if File.exists?(oas3_yaml)
            details = Details.new(PathInfo.new(oas3_yaml))
            content = File.read(oas3_yaml, encoding: "utf-8", invalid: :skip)
            yaml_obj = parse_yaml(content)

            base_path = @url
            begin
              base_path = get_base_path yaml_obj["servers"]
            rescue e
              @logger.debug "Exception of #{oas3_yaml}/servers"
              @logger.debug_sub e
            end

            process_paths_yaml(yaml_obj, base_path, details, oas3_yaml)
          end
        end
      end

      @result
    end

    private def process_paths_json(json_obj : JSON::Any, base_path : String, details : Details, source : String)
      schemes = security_schemes_json(json_obj)
      global_security = json_obj["security"]?
      paths = json_obj["paths"].as_h
      paths.each do |path, path_obj|
        path_item = resolve_path_item_json(json_obj, path_obj)
        path_level_params = [] of Param
        if path_obj_h = path_item.as_h?
          if shared = path_obj_h["parameters"]?.try(&.as_a?)
            shared.each do |param_obj|
              extract_param_json(json_obj, param_obj, path_level_params)
            end
          end
        end

        path_item.as_h.each do |method, method_obj|
          next unless HTTP_METHODS.includes?(method.to_s.downcase)
          params = path_level_params.dup
          effective_security = global_security

          begin
            if method_obj_h = method_obj.as_h?
              if method_params = method_obj_h["parameters"]?.try(&.as_a?)
                method_params.each do |param_obj|
                  extract_param_json(json_obj, param_obj, params)
                end
              end

              if request_body = method_obj_h["requestBody"]?
                extract_request_body_json(json_obj, request_body, params)
              end

              effective_security = method_obj_h["security"] if method_obj_h.has_key?("security")
            end
          rescue e
            @logger.debug "Exception of #{source}/paths/method/parameters"
            @logger.debug_sub e
          end

          apply_security_json(effective_security, schemes, params)

          if params.size > 0
            @result << Endpoint.new(base_path + path, method.upcase, params, details)
          else
            @result << Endpoint.new(base_path + path, method.upcase, details)
          end
        rescue e
          @logger.debug "Exception of #{source}/paths/endpoint"
          @logger.debug_sub e
        end
      end
    rescue e
      @logger.debug "Exception of #{source}/paths"
      @logger.debug_sub e
    end

    private def process_paths_yaml(yaml_obj : YAML::Any, base_path : String, details : Details, source : String)
      schemes = security_schemes_yaml(yaml_obj)
      global_security = yaml_obj[YAML::Any.new("security")]?
      paths = yaml_obj["paths"].as_h
      paths.each do |path, path_obj|
        path_item = resolve_path_item_yaml(yaml_obj, path_obj)
        path_level_params = [] of Param
        if path_obj_h = path_item.as_h?
          if shared_node = path_obj_h[YAML::Any.new("parameters")]?
            if shared = shared_node.as_a?
              shared.each do |param_obj|
                extract_param_yaml(yaml_obj, param_obj, path_level_params)
              end
            end
          end
        end

        path_item.as_h.each do |method, method_obj|
          next unless HTTP_METHODS.includes?(method.to_s.downcase)
          params = path_level_params.dup
          effective_security = global_security

          begin
            if method_obj_h = method_obj.as_h?
              if method_params_node = method_obj_h[YAML::Any.new("parameters")]?
                if method_params = method_params_node.as_a?
                  method_params.each do |param_obj|
                    extract_param_yaml(yaml_obj, param_obj, params)
                  end
                end
              end

              if request_body = method_obj_h[YAML::Any.new("requestBody")]?
                extract_request_body_yaml(yaml_obj, request_body, params)
              end

              effective_security = method_obj_h[YAML::Any.new("security")] if method_obj_h.has_key?(YAML::Any.new("security"))
            end
          rescue e
            @logger.debug "Exception of #{source}/paths/method/parameters"
            @logger.debug_sub e
          end

          apply_security_yaml(effective_security, schemes, params)

          if params.size > 0
            @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params, details)
          else
            @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, details)
          end
        rescue e
          @logger.debug "Exception of #{source}/paths/endpoint"
          @logger.debug_sub e
        end
      end
    rescue e
      @logger.debug "Exception of #{source}/paths"
      @logger.debug_sub e
    end
  end
end
