require "../../engines/specification_engine"
require "../../../utils/yaml"
require "uri"

module Analyzer::Specification
  class Oas3 < SpecificationEngine
    analyzer_for "oas3"

    # `query` is the OpenAPI 3.2 Path Item operation key for RFC 10008's
    # QUERY method; the detector accepts every 3.x document, so a spec
    # declaring it must not have the operation silently skipped.
    HTTP_METHODS = {"get", "post", "put", "delete", "patch", "options", "head", "trace", "query"}

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

    # Walks an OAS3 schema, emitting one Param per top-level property.
    # Follows `$ref` and flattens `allOf` so referenced/composed schemas
    # surface their members.
    private def collect_schema_props_json(doc : SpecDoc(JSON::Any), schema : JSON::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # JSON Schema allows boolean `items` etc.; a scalar node makes the
      # `["..."]?` subscripts below raise "Expected Hash".
      return unless schema.as_h?
      if ref = schema["$ref"]?.try(&.as_s?)
        return unless seen.add?(ref_key(doc, ref))
        if resolved = resolve_ref_json(doc, ref)
          node, ref_doc = resolved
          collect_schema_props_json(ref_doc, node, param_type, params, seen)
        end
        return
      end

      if items = schema["items"]?
        collect_schema_props_json(doc, items, param_type, params, seen)
      end

      if props = schema["properties"]?.try(&.as_h?)
        props.each do |name, _|
          add_param(params, name.to_s, param_type)
        end
      end

      if all_of = schema["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_schema_props_json(doc, s, param_type, params, seen) }
      end

      if one_of = schema["oneOf"]?.try(&.as_a?)
        one_of.each { |s| collect_schema_props_json(doc, s, param_type, params, seen) }
      end

      if any_of = schema["anyOf"]?.try(&.as_a?)
        any_of.each { |s| collect_schema_props_json(doc, s, param_type, params, seen) }
      end
    end

    private def collect_schema_props_yaml(doc : SpecDoc(YAML::Any), schema : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # JSON Schema allows boolean `items` etc.; a scalar node makes the
      # `[...]?` subscripts below raise "Expected Hash".
      return unless schema.as_h?
      if ref_node = schema[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return unless seen.add?(ref_key(doc, ref))
          if resolved = resolve_ref_yaml(doc, ref)
            node, ref_doc = resolved
            collect_schema_props_yaml(ref_doc, node, param_type, params, seen)
          end
        end
        return
      end

      if items_node = schema[YAML::Any.new("items")]?
        collect_schema_props_yaml(doc, items_node, param_type, params, seen)
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
          all_of.each { |s| collect_schema_props_yaml(doc, s, param_type, params, seen) }
        end
      end

      if one_of_node = schema[YAML::Any.new("oneOf")]?
        if one_of = one_of_node.as_a?
          one_of.each { |s| collect_schema_props_yaml(doc, s, param_type, params, seen) }
        end
      end

      if any_of_node = schema[YAML::Any.new("anyOf")]?
        if any_of = any_of_node.as_a?
          any_of.each { |s| collect_schema_props_yaml(doc, s, param_type, params, seen) }
        end
      end
    end

    # `seen` is not optional bookkeeping here: a parameter may be a `$ref` to
    # a parameter that is itself a `$ref`, and two documents that name each
    # other would otherwise recurse until the stack ran out.
    private def extract_param_json(doc : SpecDoc(JSON::Any), param_obj : JSON::Any, params : Array(Param), seen : Set(String) = Set(String).new)
      if ref = param_obj["$ref"]?.try(&.as_s?)
        return unless seen.add?(ref_key(doc, ref))
        if resolved = resolve_ref_json(doc, ref)
          node, ref_doc = resolved
          extract_param_json(ref_doc, node, params, seen)
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

    private def extract_param_yaml(doc : SpecDoc(YAML::Any), param_obj : YAML::Any, params : Array(Param), seen : Set(String) = Set(String).new)
      if ref_node = param_obj[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return unless seen.add?(ref_key(doc, ref))
          if resolved = resolve_ref_yaml(doc, ref)
            node, ref_doc = resolved
            extract_param_yaml(ref_doc, node, params, seen)
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
    private def security_schemes_json(doc : SpecDoc(JSON::Any)) : Hash(String, Param)
      result = {} of String => Param
      return result unless components = doc.root["components"]?.try(&.as_h?)
      return result unless schemes = components["securitySchemes"]?.try(&.as_h?)
      schemes.each do |name, obj|
        if param = security_scheme_param_json(doc, obj)
          result[name.to_s] = param
        end
      end
      result
    end

    private def security_scheme_param_json(doc : SpecDoc(JSON::Any), obj : JSON::Any, seen : Set(String) = Set(String).new) : Param?
      return unless obj_h = obj.as_h?
      if ref = obj_h["$ref"]?.try(&.as_s?)
        return unless seen.add?(ref_key(doc, ref))
        if resolved = resolve_ref_json(doc, ref)
          node, ref_doc = resolved
          return security_scheme_param_json(ref_doc, node, seen)
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

    private def security_schemes_yaml(doc : SpecDoc(YAML::Any)) : Hash(String, Param)
      result = {} of String => Param
      return result unless components = doc.root[YAML::Any.new("components")]?.try(&.as_h?)
      return result unless schemes = components[YAML::Any.new("securitySchemes")]?.try(&.as_h?)
      schemes.each do |name, obj|
        if param = security_scheme_param_yaml(doc, obj)
          result[name.to_s] = param
        end
      end
      result
    end

    private def security_scheme_param_yaml(doc : SpecDoc(YAML::Any), obj : YAML::Any, seen : Set(String) = Set(String).new) : Param?
      return unless obj_h = obj.as_h?
      if ref_node = obj_h[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return unless seen.add?(ref_key(doc, ref))
          if resolved = resolve_ref_yaml(doc, ref)
            node, ref_doc = resolved
            return security_scheme_param_yaml(ref_doc, node, seen)
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

    # Resolves the `$ref` a Path Item may stand in for, and reports which
    # document the result came from: with the operations in
    # `./paths/activity/activities.yaml`, every ref inside them resolves from
    # that file, not from the entry document that named it.
    private def resolve_path_item_json(doc : SpecDoc(JSON::Any), path_obj : JSON::Any, seen : Set(String) = Set(String).new) : Tuple(JSON::Any, SpecDoc(JSON::Any))
      return {path_obj, doc} unless path_obj_h = path_obj.as_h?
      return {path_obj, doc} unless ref = path_obj_h["$ref"]?.try(&.as_s?)
      return {path_obj, doc} unless seen.add?(ref_key(doc, ref))
      if resolved = resolve_ref_json(doc, ref)
        node, ref_doc = resolved
        resolve_path_item_json(ref_doc, node, seen)
      else
        {path_obj, doc}
      end
    end

    private def resolve_path_item_yaml(doc : SpecDoc(YAML::Any), path_obj : YAML::Any, seen : Set(String) = Set(String).new) : Tuple(YAML::Any, SpecDoc(YAML::Any))
      return {path_obj, doc} unless path_obj_h = path_obj.as_h?
      return {path_obj, doc} unless ref_node = path_obj_h[YAML::Any.new("$ref")]?
      return {path_obj, doc} unless ref = ref_node.as_s?
      return {path_obj, doc} unless seen.add?(ref_key(doc, ref))
      if resolved = resolve_ref_yaml(doc, ref)
        node, ref_doc = resolved
        resolve_path_item_yaml(ref_doc, node, seen)
      else
        {path_obj, doc}
      end
    end

    private def extract_request_body_json(doc : SpecDoc(JSON::Any), request_body : JSON::Any, params : Array(Param), seen : Set(String) = Set(String).new)
      # The requestBody object itself can be $ref'd to components.requestBodies.
      if ref = request_body["$ref"]?.try(&.as_s?)
        return unless seen.add?(ref_key(doc, ref))
        if resolved = resolve_ref_json(doc, ref)
          node, ref_doc = resolved
          extract_request_body_json(ref_doc, node, params, seen)
        end
        return
      end
      return unless content = request_body["content"]?.try(&.as_h?)
      content.each do |content_type, content_obj|
        next unless param_type = param_type_for_content(content_type.to_s)
        if schema = content_obj["schema"]?
          collect_schema_props_json(doc, schema, param_type, params)
        end
      end
    end

    private def extract_request_body_yaml(doc : SpecDoc(YAML::Any), request_body : YAML::Any, params : Array(Param), seen : Set(String) = Set(String).new)
      if ref_node = request_body[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return unless seen.add?(ref_key(doc, ref))
          if resolved = resolve_ref_yaml(doc, ref)
            node, ref_doc = resolved
            extract_request_body_yaml(ref_doc, node, params, seen)
          end
        end
        return
      end
      return unless content_node = request_body[YAML::Any.new("content")]?
      return unless content = content_node.as_h?
      content.each do |content_type, content_obj|
        next unless param_type = param_type_for_content(content_type.to_s)
        if schema_node = content_obj[YAML::Any.new("schema")]?
          collect_schema_props_yaml(doc, schema_node, param_type, params)
        end
      end
    end

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::OAS3_JSON) do |oas3_json, details|
        content = read_file_content(oas3_json)
        json_obj = JSON.parse(content)

        base_path = @url
        begin
          base_path = get_base_path json_obj["servers"]
        rescue e
          @logger.debug "Exception of #{oas3_json}/servers"
          @logger.debug_sub e
        end

        process_paths_json(SpecDoc.new(json_obj, oas3_json), base_path, details,
          Noir::SpecLineIndex.json(content, "paths"))
      end

      each_spec_file_with_details(Noir::LocatorKeys::OAS3_YAML) do |oas3_yaml, details|
        content = read_file_content(oas3_yaml)
        yaml_obj = parse_yaml(content)

        base_path = @url
        begin
          base_path = get_base_path yaml_obj["servers"]
        rescue e
          @logger.debug "Exception of #{oas3_yaml}/servers"
          @logger.debug_sub e
        end

        process_paths_yaml(SpecDoc.new(yaml_obj, oas3_yaml), base_path, details,
          Noir::SpecLineIndex.yaml(content, "paths"))
      end

      @result
    end

    private def process_paths_json(doc : SpecDoc(JSON::Any), base_path : String, details : Details,
                                   line_index : Noir::SpecLineIndex)
      schemes = security_schemes_json(doc)
      global_security = doc.root["security"]?
      paths = doc.root["paths"].as_h
      paths.each do |path, path_obj|
        path_item, item_doc = resolve_path_item_json(doc, path_obj)
        # A Path Item that did not resolve to a mapping — a ref to a scalar,
        # a `null` entry — costs itself and nothing else. Calling `as_h` on
        # it below would raise past the loop and take every path after it,
        # which is precisely how one unreadable ref used to lose a whole
        # document.
        next unless path_item_h = path_item.as_h?

        path_level_params = [] of Param
        if shared = path_item_h["parameters"]?.try(&.as_a?)
          shared.each do |param_obj|
            extract_param_json(item_doc, param_obj, path_level_params)
          end
        end

        path_item_h.each do |method, method_obj|
          next unless HTTP_METHODS.includes?(method.to_s.downcase)
          params = path_level_params.dup
          effective_security = global_security

          begin
            if method_obj_h = method_obj.as_h?
              if method_params = method_obj_h["parameters"]?.try(&.as_a?)
                method_params.each do |param_obj|
                  extract_param_json(item_doc, param_obj, params)
                end
              end

              if request_body = method_obj_h["requestBody"]?
                extract_request_body_json(item_doc, request_body, params)
              end

              effective_security = method_obj_h["security"] if method_obj_h.has_key?("security")
            end
          rescue e
            @logger.debug "Exception of #{item_doc.path}/paths/method/parameters"
            @logger.debug_sub e
          end

          apply_security_json(effective_security, schemes, params)

          op_details = operation_details(details, line_index, ["paths", path, method])
          if params.size > 0
            @result << Endpoint.new(base_path + path, method.upcase, params, op_details)
          else
            @result << Endpoint.new(base_path + path, method.upcase, op_details)
          end
        rescue e
          @logger.debug "Exception of #{doc.path}/paths/endpoint"
          @logger.debug_sub e
        end
      end
    rescue e
      @logger.debug "Exception of #{doc.path}/paths"
      @logger.debug_sub e
    end

    private def process_paths_yaml(doc : SpecDoc(YAML::Any), base_path : String, details : Details,
                                   line_index : Noir::SpecLineIndex)
      schemes = security_schemes_yaml(doc)
      global_security = doc.root[YAML::Any.new("security")]?
      paths = doc.root["paths"].as_h
      paths.each do |path, path_obj|
        path_item, item_doc = resolve_path_item_yaml(doc, path_obj)
        # See `process_paths_json`: a Path Item that is not a mapping must
        # not take the paths after it down with it.
        next unless path_item_h = path_item.as_h?

        path_level_params = [] of Param
        if shared_node = path_item_h[YAML::Any.new("parameters")]?
          if shared = shared_node.as_a?
            shared.each do |param_obj|
              extract_param_yaml(item_doc, param_obj, path_level_params)
            end
          end
        end

        path_item_h.each do |method, method_obj|
          next unless HTTP_METHODS.includes?(method.to_s.downcase)
          params = path_level_params.dup
          effective_security = global_security

          begin
            if method_obj_h = method_obj.as_h?
              if method_params_node = method_obj_h[YAML::Any.new("parameters")]?
                if method_params = method_params_node.as_a?
                  method_params.each do |param_obj|
                    extract_param_yaml(item_doc, param_obj, params)
                  end
                end
              end

              if request_body = method_obj_h[YAML::Any.new("requestBody")]?
                extract_request_body_yaml(item_doc, request_body, params)
              end

              effective_security = method_obj_h[YAML::Any.new("security")] if method_obj_h.has_key?(YAML::Any.new("security"))
            end
          rescue e
            @logger.debug "Exception of #{item_doc.path}/paths/method/parameters"
            @logger.debug_sub e
          end

          apply_security_yaml(effective_security, schemes, params)

          op_details = operation_details(details, line_index, ["paths", path.to_s, method.to_s])
          if params.size > 0
            @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params, op_details)
          else
            @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, op_details)
          end
        rescue e
          @logger.debug "Exception of #{doc.path}/paths/endpoint"
          @logger.debug_sub e
        end
      end
    rescue e
      @logger.debug "Exception of #{doc.path}/paths"
      @logger.debug_sub e
    end
  end
end
