require "../../../models/analyzer"

module Analyzer::Specification
  class Oas2 < Analyzer
    HTTP_METHODS = {"get", "post", "put", "delete", "patch", "options", "head", "trace"}

    # Resolves a `#/definitions/Name` pointer against the spec root.
    # Returns the referenced node, or nil when the ref cannot be followed.
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

    # Walks a body schema and emits a Param per top-level property.
    private def collect_body_props_json(root : JSON::Any, schema : JSON::Any, param_type : String, params : Array(Param))
      if ref = schema["$ref"]?.try(&.as_s?)
        if resolved = resolve_ref_json(root, ref)
          collect_body_props_json(root, resolved, param_type, params)
        end
        return
      end

      if props = schema["properties"]?.try(&.as_h?)
        props.each do |name, _|
          params << Param.new(name.to_s, "", param_type)
        end
      end

      if all_of = schema["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_body_props_json(root, s, param_type, params) }
      end
    end

    private def collect_body_props_yaml(root : YAML::Any, schema : YAML::Any, param_type : String, params : Array(Param))
      if ref_node = schema[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          if resolved = resolve_ref_yaml(root, ref)
            collect_body_props_yaml(root, resolved, param_type, params)
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
          all_of.each { |s| collect_body_props_yaml(root, s, param_type, params) }
        end
      end
    end

    # Maps an OAS2 parameter object onto Noir's Param types.
    # `consumes` lets body params pick form vs. json when the route advertises
    # `multipart/form-data` or `application/x-www-form-urlencoded`.
    private def param_type_for_body(consumes : Array(String)) : String
      if consumes.any? { |c| c.starts_with?("multipart/form-data") || c.starts_with?("application/x-www-form-urlencoded") }
        "form"
      else
        "json"
      end
    end

    private def extract_param_json(root : JSON::Any, param_obj : JSON::Any, consumes : Array(String), params : Array(Param))
      # Parameters can themselves be $ref'd.
      if ref = param_obj["$ref"]?.try(&.as_s?)
        if resolved = resolve_ref_json(root, ref)
          extract_param_json(root, resolved, consumes, params)
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
      when "form", "formData"
        params << Param.new(name, "", "form")
      when "body"
        if schema = param_obj["schema"]?
          collect_body_props_json(root, schema, param_type_for_body(consumes), params)
        end
      end
    end

    private def extract_param_yaml(root : YAML::Any, param_obj : YAML::Any, consumes : Array(String), params : Array(Param))
      if ref_node = param_obj[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          if resolved = resolve_ref_yaml(root, ref)
            extract_param_yaml(root, resolved, consumes, params)
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
      when "form", "formData"
        params << Param.new(name, "", "form")
      when "body"
        if schema = param_obj[YAML::Any.new("schema")]?
          collect_body_props_yaml(root, schema, param_type_for_body(consumes), params)
        end
      end
    end

    private def consumes_json(root : JSON::Any, method_obj : JSON::Any) : Array(String)
      list = [] of String
      if method_consumes = method_obj["consumes"]?.try(&.as_a?)
        method_consumes.each { |c| list << c.to_s }
      elsif global = root["consumes"]?.try(&.as_a?)
        global.each { |c| list << c.to_s }
      end
      list
    end

    private def consumes_yaml(root : YAML::Any, method_obj : YAML::Any) : Array(String)
      list = [] of String
      if method_consumes_node = method_obj[YAML::Any.new("consumes")]?
        if arr = method_consumes_node.as_a?
          arr.each { |c| list << c.to_s }
        end
      elsif global_node = root[YAML::Any.new("consumes")]?
        if arr = global_node.as_a?
          arr.each { |c| list << c.to_s }
        end
      end
      list
    end

    def analyze
      locator = CodeLocator.instance
      swagger_jsons = locator.all("swagger-json")
      swagger_yamls = locator.all("swagger-yaml")

      if swagger_jsons.is_a?(Array(String))
        swagger_jsons.each { |path| process_json(path) }
      end

      if swagger_yamls.is_a?(Array(String))
        swagger_yamls.each { |path| process_yaml(path) }
      end

      @result
    end

    private def process_json(swagger_json : String)
      return unless File.exists?(swagger_json)
      details = Details.new(PathInfo.new(swagger_json))
      content = File.read(swagger_json, encoding: "utf-8", invalid: :skip)
      json_obj = JSON.parse(content)
      base_path = ""
      begin
        if json_obj["basePath"].to_s != ""
          base_path = json_obj["basePath"].to_s
        end
      rescue e
        @logger.debug "Exception of #{swagger_json}/basePath"
        @logger.debug_sub e
      end

      begin
        paths = json_obj["paths"].as_h
        paths.each do |path, path_obj|
          path_level_params = [] of Param
          if path_obj_h = path_obj.as_h?
            if shared = path_obj_h["parameters"]?.try(&.as_a?)
              shared.each do |param_obj|
                extract_param_json(json_obj, param_obj, [] of String, path_level_params)
              end
            end
          end

          path_obj.as_h.each do |method, method_obj|
            next unless HTTP_METHODS.includes?(method.to_s.downcase)
            params = path_level_params.dup
            consumes = consumes_json(json_obj, method_obj)

            if method_params = method_obj["parameters"]?.try(&.as_a?)
              method_params.each do |param_obj|
                extract_param_json(json_obj, param_obj, consumes, params)
              end
            end

            if params.size > 0
              @result << Endpoint.new(base_path + path, method.upcase, params, details)
            else
              @result << Endpoint.new(base_path + path, method.upcase, details)
            end
          rescue e
            @logger.debug "Exception of #{swagger_json}/paths/path/method"
            @logger.debug_sub e
          end
        rescue e
          @logger.debug "Exception of #{swagger_json}/paths/path"
          @logger.debug_sub e
        end
      rescue e
        @logger.debug "Exception of #{swagger_json}/paths"
        @logger.debug_sub e
      end
    end

    private def process_yaml(swagger_yaml : String)
      return unless File.exists?(swagger_yaml)
      details = Details.new(PathInfo.new(swagger_yaml))
      content = File.read(swagger_yaml, encoding: "utf-8", invalid: :skip)
      yaml_obj = YAML.parse(content)
      base_path = ""
      begin
        if yaml_obj["basePath"].to_s != ""
          base_path = yaml_obj["basePath"].to_s
        end
      rescue e
        @logger.debug "Exception of #{swagger_yaml}/basePath"
        @logger.debug_sub e
      end

      begin
        paths = yaml_obj["paths"].as_h
        paths.each do |path, path_obj|
          path_level_params = [] of Param
          if path_obj_h = path_obj.as_h?
            if shared_node = path_obj_h[YAML::Any.new("parameters")]?
              if shared = shared_node.as_a?
                shared.each do |param_obj|
                  extract_param_yaml(yaml_obj, param_obj, [] of String, path_level_params)
                end
              end
            end
          end

          path_obj.as_h.each do |method, method_obj|
            next unless HTTP_METHODS.includes?(method.to_s.downcase)
            params = path_level_params.dup
            consumes = consumes_yaml(yaml_obj, method_obj)

            if method_params_node = method_obj[YAML::Any.new("parameters")]?
              if method_params = method_params_node.as_a?
                method_params.each do |param_obj|
                  extract_param_yaml(yaml_obj, param_obj, consumes, params)
                end
              end
            end

            if params.size > 0
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params, details)
            else
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, details)
            end
          rescue e
            @logger.debug "Exception of #{swagger_yaml}/paths/path/method"
            @logger.debug_sub e
          end
        rescue e
          @logger.debug "Exception of #{swagger_yaml}/paths/path"
          @logger.debug_sub e
        end
      rescue e
        @logger.debug "Exception of #{swagger_yaml}/paths"
        @logger.debug_sub e
      end
    end
  end
end
