require "../../../models/analyzer"
require "../../../utils/yaml"

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

    private def add_param(params : Array(Param), name : String, param_type : String)
      return if name.empty?
      param = Param.new(name, "", param_type)
      params << param unless params.includes?(param)
    end

    # Walks a body schema and emits a Param per top-level property.
    private def collect_body_props_json(root : JSON::Any, schema : JSON::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      if ref = schema["$ref"]?.try(&.as_s?)
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          collect_body_props_json(root, resolved, param_type, params, seen)
        end
        return
      end

      if items = schema["items"]?
        collect_body_props_json(root, items, param_type, params, seen)
      end

      if props = schema["properties"]?.try(&.as_h?)
        props.each do |name, _|
          add_param(params, name.to_s, param_type)
        end
      end

      if all_of = schema["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_body_props_json(root, s, param_type, params, seen) }
      end

      if one_of = schema["oneOf"]?.try(&.as_a?)
        one_of.each { |s| collect_body_props_json(root, s, param_type, params, seen) }
      end

      if any_of = schema["anyOf"]?.try(&.as_a?)
        any_of.each { |s| collect_body_props_json(root, s, param_type, params, seen) }
      end
    end

    private def collect_body_props_yaml(root : YAML::Any, schema : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      if ref_node = schema[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return if seen.includes?(ref)
          seen << ref
          if resolved = resolve_ref_yaml(root, ref)
            collect_body_props_yaml(root, resolved, param_type, params, seen)
          end
        end
        return
      end

      if items_node = schema[YAML::Any.new("items")]?
        collect_body_props_yaml(root, items_node, param_type, params, seen)
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
          all_of.each { |s| collect_body_props_yaml(root, s, param_type, params, seen) }
        end
      end

      if one_of_node = schema[YAML::Any.new("oneOf")]?
        if one_of = one_of_node.as_a?
          one_of.each { |s| collect_body_props_yaml(root, s, param_type, params, seen) }
        end
      end

      if any_of_node = schema[YAML::Any.new("anyOf")]?
        if any_of = any_of_node.as_a?
          any_of.each { |s| collect_body_props_yaml(root, s, param_type, params, seen) }
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
      when "body"
        if schema = param_obj["schema"]?
          collect_body_props_json(root, schema, param_type_for_body(consumes), params)
        end
      else
        return if name.empty?
        case location
        when "query"
          add_param(params, name, "query")
        when "header"
          add_param(params, name, "header")
        when "form", "formData"
          add_param(params, name, "form")
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
      when "body"
        if schema = param_obj[YAML::Any.new("schema")]?
          collect_body_props_yaml(root, schema, param_type_for_body(consumes), params)
        end
      else
        return if name.empty?
        case location
        when "query"
          add_param(params, name, "query")
        when "header"
          add_param(params, name, "header")
        when "form", "formData"
          add_param(params, name, "form")
        end
      end
    end

    # Builds `scheme name => Param` from OAS2 `securityDefinitions`. An `apiKey`
    # scheme is a concrete request parameter (header/query); `basic`/`oauth2`
    # ride on the `Authorization` header. Mirrors the Insomnia analyzer so a
    # documented requirement isn't a false negative.
    private def security_schemes_json(root : JSON::Any) : Hash(String, Param)
      result = {} of String => Param
      return result unless defs = root["securityDefinitions"]?.try(&.as_h?)
      defs.each do |name, obj|
        if param = security_scheme_param_json(obj)
          result[name.to_s] = param
        end
      end
      result
    end

    private def security_scheme_param_json(obj : JSON::Any) : Param?
      return unless obj_h = obj.as_h?
      case obj_h["type"]?.try(&.as_s?).try(&.downcase)
      when "apikey"
        name = obj_h["name"]?.try(&.as_s?) || ""
        return if name.empty?
        case obj_h["in"]?.try(&.as_s?)
        when "header" then Param.new(name, "", "header")
        when "query"  then Param.new(name, "", "query")
        end
      when "basic", "oauth2"
        Param.new("Authorization", "", "header")
      end
    end

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
      return result unless defs = root[YAML::Any.new("securityDefinitions")]?.try(&.as_h?)
      defs.each do |name, obj|
        if param = security_scheme_param_yaml(obj)
          result[name.to_s] = param
        end
      end
      result
    end

    private def security_scheme_param_yaml(obj : YAML::Any) : Param?
      return unless obj_h = obj.as_h?
      case obj_h[YAML::Any.new("type")]?.try(&.as_s?).try(&.downcase)
      when "apikey"
        name = obj_h[YAML::Any.new("name")]?.try(&.as_s?) || ""
        return if name.empty?
        case obj_h[YAML::Any.new("in")]?.try(&.as_s?)
        when "header" then Param.new(name, "", "header")
        when "query"  then Param.new(name, "", "query")
        end
      when "basic", "oauth2"
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
        unless json_obj["basePath"].to_s.empty?
          base_path = json_obj["basePath"].to_s
        end
      rescue e
        @logger.debug "Exception of #{swagger_json}/basePath"
        @logger.debug_sub e
      end

      schemes = security_schemes_json(json_obj)
      global_security = json_obj["security"]?
      begin
        paths = json_obj["paths"].as_h
        paths.each do |path, path_obj|
          path_item = resolve_path_item_json(json_obj, path_obj)
          path_level_params = [] of JSON::Any
          if path_obj_h = path_item.as_h?
            if shared = path_obj_h["parameters"]?.try(&.as_a?)
              path_level_params.concat(shared)
            end
          end

          path_item.as_h.each do |method, method_obj|
            next unless HTTP_METHODS.includes?(method.to_s.downcase)
            params = [] of Param
            consumes = consumes_json(json_obj, method_obj)
            path_level_params.each do |param_obj|
              extract_param_json(json_obj, param_obj, consumes, params)
            end

            if method_params = method_obj["parameters"]?.try(&.as_a?)
              method_params.each do |param_obj|
                extract_param_json(json_obj, param_obj, consumes, params)
              end
            end

            effective_security = global_security
            if method_obj_h = method_obj.as_h?
              effective_security = method_obj_h["security"] if method_obj_h.has_key?("security")
            end
            apply_security_json(effective_security, schemes, params)

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
      yaml_obj = parse_yaml(content)
      base_path = ""
      begin
        unless yaml_obj["basePath"].to_s.empty?
          base_path = yaml_obj["basePath"].to_s
        end
      rescue e
        @logger.debug "Exception of #{swagger_yaml}/basePath"
        @logger.debug_sub e
      end

      schemes = security_schemes_yaml(yaml_obj)
      global_security = yaml_obj[YAML::Any.new("security")]?
      begin
        paths = yaml_obj["paths"].as_h
        paths.each do |path, path_obj|
          path_item = resolve_path_item_yaml(yaml_obj, path_obj)
          path_level_params = [] of YAML::Any
          if path_obj_h = path_item.as_h?
            if shared_node = path_obj_h[YAML::Any.new("parameters")]?
              if shared = shared_node.as_a?
                path_level_params.concat(shared)
              end
            end
          end

          path_item.as_h.each do |method, method_obj|
            next unless HTTP_METHODS.includes?(method.to_s.downcase)
            params = [] of Param
            consumes = consumes_yaml(yaml_obj, method_obj)
            path_level_params.each do |param_obj|
              extract_param_yaml(yaml_obj, param_obj, consumes, params)
            end

            if method_params_node = method_obj[YAML::Any.new("parameters")]?
              if method_params = method_params_node.as_a?
                method_params.each do |param_obj|
                  extract_param_yaml(yaml_obj, param_obj, consumes, params)
                end
              end
            end

            effective_security = global_security
            if method_obj_h = method_obj.as_h?
              effective_security = method_obj_h[YAML::Any.new("security")] if method_obj_h.has_key?(YAML::Any.new("security"))
            end
            apply_security_yaml(effective_security, schemes, params)

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
