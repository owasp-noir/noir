require "../../../models/analyzer"

module Analyzer::Specification
  class RAML < Analyzer
    HTTP_METHODS = {"get", "post", "put", "delete", "patch", "options", "head"}

    def analyze
      locator = CodeLocator.instance
      raml_specs = locator.all("raml-spec")

      if raml_specs.is_a?(Array(String))
        raml_specs.each do |raml_spec|
          next unless File.exists?(raml_spec)
          details = Details.new(PathInfo.new(raml_spec))
          content = File.read(raml_spec, encoding: "utf-8", invalid: :skip)
          yaml_obj = YAML.parse(content)

          base_path = base_path_from(yaml_obj)
          default_media = yaml_obj[YAML::Any.new("mediaType")]?.try(&.to_s) || "application/json"
          types = yaml_obj[YAML::Any.new("types")]? || YAML::Any.new(nil)

          if root = yaml_obj.as_h?
            root.each do |key, value|
              key_s = key.to_s
              next unless key_s.starts_with?("/")
              walk_resource(value, base_path + key_s, default_media, types, details, raml_spec)
            end
          end
        end
      end

      @result
    end

    # RAML `baseUri` may be a full URL; we keep just the path so endpoints
    # render in Noir's relative form, mirroring how OAS3 `servers` is handled.
    private def base_path_from(yaml_obj : YAML::Any) : String
      base_uri = yaml_obj[YAML::Any.new("baseUri")]?.try(&.to_s) || ""
      return "" if base_uri.empty?
      if base_uri.starts_with?("http")
        begin
          uri = URI.parse(base_uri)
          return (uri.path || "").rstrip('/')
        rescue
          return ""
        end
      end
      base_uri.rstrip('/')
    end

    # Resources nest under each other in RAML. Each `/segment` key under a
    # resource is itself a resource, so we recurse and accumulate the path.
    private def walk_resource(node : YAML::Any, path : String, default_media : String, types : YAML::Any, details : Details, source : String)
      return unless h = node.as_h?

      resource_uri_params = [] of Param
      if up_node = h[YAML::Any.new("uriParameters")]?
        if up = up_node.as_h?
          up.each do |name, _|
            resource_uri_params << Param.new(name.to_s, "", "path")
          end
        end
      end

      h.each do |key, value|
        key_s = key.to_s
        if HTTP_METHODS.includes?(key_s.downcase)
          build_endpoint(path, key_s, value, resource_uri_params, default_media, types, details, source)
        elsif key_s.starts_with?("/")
          walk_resource(value, path + key_s, default_media, types, details, source)
        end
      end
    rescue e
      @logger.debug "Exception of #{source}/#{path}"
      @logger.debug_sub e
    end

    private def build_endpoint(path : String, method : String, method_node : YAML::Any, uri_params : Array(Param), default_media : String, types : YAML::Any, details : Details, source : String)
      params = uri_params.dup

      if h = method_node.as_h?
        if qp_node = h[YAML::Any.new("queryParameters")]?
          if qp = qp_node.as_h?
            qp.each do |name, _|
              params << Param.new(name.to_s, "", "query")
            end
          end
        end

        if hdr_node = h[YAML::Any.new("headers")]?
          if hdr = hdr_node.as_h?
            hdr.each do |name, _|
              params << Param.new(name.to_s, "", "header")
            end
          end
        end

        if body_node = h[YAML::Any.new("body")]?
          extract_body(body_node, default_media, types, params)
        end
      end

      @result << Endpoint.new(path, method.upcase, params, details)
    rescue e
      @logger.debug "Exception of #{source}/#{path}/#{method}"
      @logger.debug_sub e
    end

    # In RAML 1.0 `body:` can be shaped two ways: either an inline schema
    # (`properties:` / `type:` at the same level, implicitly default media
    # type) or a hash keyed by media type. Handle both forms.
    private def extract_body(body_node : YAML::Any, default_media : String, types : YAML::Any, params : Array(Param))
      return unless body_h = body_node.as_h?

      shorthand = false
      if body_h.has_key?(YAML::Any.new("properties")) || body_h.has_key?(YAML::Any.new("type"))
        shorthand = true
      end

      if shorthand
        media_param_type = param_type_for_media(default_media)
        collect_body_props(body_node, types, media_param_type, params) if media_param_type
        return
      end

      body_h.each do |content_type_node, content_obj|
        content_type = content_type_node.to_s
        next unless param_type = param_type_for_media(content_type)
        collect_body_props(content_obj, types, param_type, params)
      end
    end

    private def param_type_for_media(media : String) : String?
      case media
      when .starts_with?("application/json")
        "json"
      when "application/x-www-form-urlencoded"
        "form"
      when .starts_with?("multipart/form-data")
        "form"
      end
    end

    # Walks a body schema for top-level property names. Supports:
    #   - `properties:` (RAML 1.0 inline)
    #   - `type: SomeType` referencing a top-level `types:` definition
    #   - `example:` as a legacy/data-only fallback when no schema is present
    private def collect_body_props(node : YAML::Any, types : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      return unless h = node.as_h?

      if props_node = h[YAML::Any.new("properties")]?
        if props = props_node.as_h?
          props.each do |name, _|
            params << Param.new(name.to_s, "", param_type)
          end
          return
        end
      end

      if type_node = h[YAML::Any.new("type")]?
        type_name = type_node.to_s
        unless seen.includes?(type_name)
          seen << type_name
          if types_h = types.as_h?
            if referenced = types_h[YAML::Any.new(type_name)]?
              collect_body_props(referenced, types, param_type, params, seen)
              return
            end
          end
        end
      end

      if ex_node = h[YAML::Any.new("example")]?
        if ex = ex_node.as_h?
          ex.each do |name, _|
            params << Param.new(name.to_s, "", param_type)
          end
        end
      end
    end
  end
end
