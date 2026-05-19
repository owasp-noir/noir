require "../../../models/analyzer"

module Analyzer::Specification
  class Oas3 < Analyzer
    HTTP_METHODS = {"get", "post", "put", "delete", "patch", "options", "head", "trace"}

    def get_base_path(servers)
      base_path = @url
      servers.as_a.each do |server_obj|
        if server_obj["url"].to_s.starts_with?("http")
          user_uri = URI.parse(@url)
          source_uri = URI.parse(server_obj["url"].to_s)
          if user_uri.host == source_uri.host
            base_path = @url + source_uri.path
            break
          end
        end
      end

      base_path
    end

    # Maps an OAS3 request-body content type to a Noir param type.
    private def param_type_for_content(content_type : String) : String?
      case content_type
      when "application/json", .starts_with?("application/json")
        "json"
      when "application/x-www-form-urlencoded"
        "form"
      when "multipart/form-data", .starts_with?("multipart/form-data")
        "form"
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

    # Walks an OAS3 schema, emitting one Param per top-level property.
    # Follows `$ref` and flattens `allOf` so referenced/composed schemas
    # surface their members.
    private def collect_schema_props_json(root : JSON::Any, schema : JSON::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      if ref = schema["$ref"]?.try(&.as_s?)
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          collect_schema_props_json(root, resolved, param_type, params, seen)
        end
        return
      end

      if props = schema["properties"]?.try(&.as_h?)
        props.each do |name, _|
          params << Param.new(name.to_s, "", param_type)
        end
      end

      if all_of = schema["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_schema_props_json(root, s, param_type, params, seen) }
      end
    end

    private def collect_schema_props_yaml(root : YAML::Any, schema : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
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

      if props_node = schema[YAML::Any.new("properties")]?
        if props = props_node.as_h?
          props.each do |name, _|
            params << Param.new(name.to_s, "", param_type)
          end
        end
      end

      if all_of_node = schema[YAML::Any.new("allOf")]?
        if all_of = all_of_node.as_a?
          all_of.each { |s| collect_schema_props_yaml(root, s, param_type, params, seen) }
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
      case location
      when "query"
        params << Param.new(name, "", "query")
      when "header"
        params << Param.new(name, "", "header")
      when "cookie"
        params << Param.new(name, "", "cookie")
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
      case location
      when "query"
        params << Param.new(name, "", "query")
      when "header"
        params << Param.new(name, "", "header")
      when "cookie"
        params << Param.new(name, "", "cookie")
      end
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
      base_path = @url

      if oas3_jsons.is_a?(Array(String))
        oas3_jsons.each do |oas3_json|
          if File.exists?(oas3_json)
            details = Details.new(PathInfo.new(oas3_json))
            content = File.read(oas3_json, encoding: "utf-8", invalid: :skip)
            json_obj = JSON.parse(content)

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
            yaml_obj = YAML.parse(content)

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
      paths = json_obj["paths"].as_h
      paths.each do |path, path_obj|
        path_level_params = [] of Param
        if path_obj_h = path_obj.as_h?
          if shared = path_obj_h["parameters"]?.try(&.as_a?)
            shared.each do |param_obj|
              extract_param_json(json_obj, param_obj, path_level_params)
            end
          end
        end

        path_obj.as_h.each do |method, method_obj|
          next unless HTTP_METHODS.includes?(method.to_s.downcase)
          params = path_level_params.dup

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
            end
          rescue e
            @logger.debug "Exception of #{source}/paths/method/parameters"
            @logger.debug_sub e
          end

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
      paths = yaml_obj["paths"].as_h
      paths.each do |path, path_obj|
        path_level_params = [] of Param
        if path_obj_h = path_obj.as_h?
          if shared_node = path_obj_h[YAML::Any.new("parameters")]?
            if shared = shared_node.as_a?
              shared.each do |param_obj|
                extract_param_yaml(yaml_obj, param_obj, path_level_params)
              end
            end
          end
        end

        path_obj.as_h.each do |method, method_obj|
          next unless HTTP_METHODS.includes?(method.to_s.downcase)
          params = path_level_params.dup

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
            end
          rescue e
            @logger.debug "Exception of #{source}/paths/method/parameters"
            @logger.debug_sub e
          end

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
