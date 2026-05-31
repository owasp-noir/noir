require "../../../models/analyzer"

module Analyzer::Specification
  class RAML < Analyzer
    HTTP_METHODS       = {"get", "post", "put", "delete", "patch", "options", "head", "trace"}
    INCLUDE_EXTENSIONS = {".raml", ".yaml", ".yml", ".json"}
    alias ResolvedNode = NamedTuple(node: YAML::Any, source_dir: String)

    def analyze
      locator = CodeLocator.instance
      raml_specs = locator.all("raml-spec")

      if raml_specs.is_a?(Array(String))
        raml_specs.each do |raml_spec|
          next unless File.exists?(raml_spec)
          details = Details.new(PathInfo.new(raml_spec))
          content = File.read(raml_spec, encoding: "utf-8", invalid: :skip)
          yaml_obj = YAML.parse(content)
          source_dir = File.dirname(raml_spec)

          base_path = base_path_from(yaml_obj)
          default_media = media_types_from(yaml_obj[YAML::Any.new("mediaType")]?)
          types = yaml_obj[YAML::Any.new("types")]? || YAML::Any.new(nil)
          schemas = yaml_obj[YAML::Any.new("schemas")]? || YAML::Any.new(nil)
          resource_types = yaml_obj[YAML::Any.new("resourceTypes")]? || YAML::Any.new(nil)
          traits = yaml_obj[YAML::Any.new("traits")]? || YAML::Any.new(nil)

          if root = yaml_obj.as_h?
            root.each do |key, value|
              key_s = key.to_s
              next unless key_s.starts_with?("/")
              walk_resource(
                value,
                base_path + key_s,
                default_media,
                types,
                schemas,
                resource_types,
                traits,
                details,
                raml_spec,
                source_dir,
                source_dir,
                [] of Param
              )
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
    private def walk_resource(
      node : YAML::Any,
      path : String,
      default_media : Array(String),
      types : YAML::Any,
      schemas : YAML::Any,
      resource_types : YAML::Any,
      traits : YAML::Any,
      details : Details,
      source : String,
      source_dir : String,
      definitions_dir : String,
      inherited_uri_params : Array(Param),
    )
      resolved = resolve_include(node, source_dir)
      node = resolved[:node]
      return unless h = node.as_h?
      type_node = resource_type_node(h, resource_types, definitions_dir)
      type_h = type_node.try(&.[:node].as_h?)
      type_dir = type_node.try(&.[:source_dir]) || source_dir

      resource_uri_params = inherited_uri_params.dup
      collect_named_params(type_h.try(&.[YAML::Any.new("uriParameters")]?), "path", resource_uri_params)
      collect_named_params(h[YAML::Any.new("uriParameters")]?, "path", resource_uri_params)

      resource_trait_refs = [] of YAML::Any
      collect_trait_refs(type_h.try(&.[YAML::Any.new("is")]?), resource_trait_refs)
      collect_trait_refs(h[YAML::Any.new("is")]?, resource_trait_refs)

      methods = Set(String).new
      collect_method_names(type_h, methods)
      collect_method_names(h, methods)

      methods.each do |method|
        operation_nodes = [] of ResolvedNode
        if type_method = lookup_case_insensitive(type_h, method)
          operation_nodes << resolve_include(type_method, type_dir)
        end
        if method_node = lookup_case_insensitive(h, method)
          operation_nodes << resolve_include(method_node, source_dir)
        end
        build_endpoint(path, method, operation_nodes, resource_trait_refs, resource_uri_params, default_media, types, schemas, traits, details, source, source_dir, definitions_dir)
      end

      child_keys = Set(String).new
      collect_child_resource_keys(type_h, child_keys, allow_templates: false)
      collect_child_resource_keys(h, child_keys, allow_templates: true)

      child_keys.each do |key_s|
        child = h[YAML::Any.new(key_s)]? || type_h.try(&.[YAML::Any.new(key_s)]?)
        next unless child
        walk_resource(
          child,
          path + key_s,
          default_media,
          types,
          schemas,
          resource_types,
          traits,
          details,
          source,
          source_dir,
          definitions_dir,
          resource_uri_params
        )
      end
    rescue e
      @logger.debug "Exception of #{source}/#{path}"
      @logger.debug_sub e
    end

    private def build_endpoint(
      path : String,
      method : String,
      operation_nodes : Array(ResolvedNode),
      resource_trait_refs : Array(YAML::Any),
      uri_params : Array(Param),
      default_media : Array(String),
      types : YAML::Any,
      schemas : YAML::Any,
      traits : YAML::Any,
      details : Details,
      source : String,
      source_dir : String,
      definitions_dir : String,
    )
      params = uri_params.dup

      resource_trait_refs.each do |trait_ref|
        apply_trait(trait_ref, default_media, types, schemas, traits, params, definitions_dir)
      end

      operation_nodes.each do |operation_node|
        operation_source_dir = operation_node[:source_dir]
        if h = operation_node[:node].as_h?
          trait_refs = [] of YAML::Any
          collect_trait_refs(h[YAML::Any.new("is")]?, trait_refs)
          trait_refs.each do |trait_ref|
            apply_trait(trait_ref, default_media, types, schemas, traits, params, definitions_dir)
          end
        end
        extract_operation_params(operation_node[:node], default_media, types, schemas, params, operation_source_dir, definitions_dir)
      end

      @result << Endpoint.new(path, method.upcase, params, details)
    rescue e
      @logger.debug "Exception of #{source}/#{path}/#{method}"
      @logger.debug_sub e
    end

    # In RAML 1.0 `body:` can be shaped two ways: either an inline schema
    # (`properties:` / `type:` at the same level, implicitly default media
    # type) or a hash keyed by media type. Handle both forms.
    private def extract_body(body_node : YAML::Any, default_media : Array(String), types : YAML::Any, schemas : YAML::Any, params : Array(Param), source_dir : String, definitions_dir : String)
      return unless body_h = body_node.as_h?

      shorthand = false
      if body_h.has_key?(YAML::Any.new("properties")) || body_h.has_key?(YAML::Any.new("type")) || body_h.has_key?(YAML::Any.new("schema"))
        shorthand = true
      end

      if shorthand
        default_media.each do |media|
          media_param_type = param_type_for_media(media)
          collect_body_props(body_node, types, schemas, media_param_type, params, source_dir, definitions_dir) if media_param_type
        end
        return
      end

      body_h.each do |content_type_node, content_obj|
        content_type = content_type_node.to_s
        next unless param_type = param_type_for_media(content_type)
        collect_body_props(content_obj, types, schemas, param_type, params, source_dir, definitions_dir)
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
    #   - `schema: SomeSchema` referencing RAML 0.8 `schemas:` definitions
    #   - `example:` as a legacy/data-only fallback when no schema is present
    private def collect_body_props(node : YAML::Any, types : YAML::Any, schemas : YAML::Any, param_type : String, params : Array(Param), source_dir : String, definitions_dir : String, seen : Set(String) = Set(String).new)
      resolved = resolve_include(node, source_dir)
      node = resolved[:node]
      return unless h = node.as_h?

      if props_node = h[YAML::Any.new("properties")]?
        if props = props_node.as_h?
          props.each do |name, _|
            add_param(params, Param.new(name.to_s, "", param_type))
          end
          return
        end
      end

      if type_node = h[YAML::Any.new("type")]?
        type_name = type_node.to_s
        if referenced = lookup_schema_definition(type_name, types, schemas, seen, definitions_dir)
          collect_body_props(referenced[:node], types, schemas, param_type, params, referenced[:source_dir], definitions_dir, seen)
          return
        end
      end

      if schema_node = h[YAML::Any.new("schema")]?
        schema_name = schema_node.to_s
        if referenced = lookup_schema_definition(schema_name, types, schemas, seen, definitions_dir)
          collect_body_props(referenced[:node], types, schemas, param_type, params, referenced[:source_dir], definitions_dir, seen)
          return
        end
      end

      if ex_node = h[YAML::Any.new("example")]?
        if ex = ex_node.as_h?
          ex.each do |name, _|
            add_param(params, Param.new(name.to_s, "", param_type))
          end
        end
      end
    end

    private def extract_operation_params(operation_node : YAML::Any, default_media : Array(String), types : YAML::Any, schemas : YAML::Any, params : Array(Param), source_dir : String, definitions_dir : String)
      return unless h = operation_node.as_h?

      collect_named_params(h[YAML::Any.new("queryParameters")]?, "query", params)
      collect_named_params(h[YAML::Any.new("headers")]?, "header", params)

      if query_string_node = h[YAML::Any.new("queryString")]?
        collect_body_props(query_string_node, types, schemas, "query", params, source_dir, definitions_dir)
      end

      if body_node = h[YAML::Any.new("body")]?
        extract_body(body_node, default_media, types, schemas, params, source_dir, definitions_dir)
      end
    end

    private def collect_named_params(node : YAML::Any?, param_type : String, params : Array(Param))
      return unless node
      return unless h = node.as_h?

      h.each do |name, _|
        next if name.to_s.includes?("<<")
        add_param(params, Param.new(name.to_s, "", param_type))
      end
    end

    private def add_param(params : Array(Param), param : Param)
      params << param unless params.includes?(param)
    end

    private def collect_method_names(h : Hash(YAML::Any, YAML::Any)?, methods : Set(String))
      return unless h

      h.each_key do |key|
        key_s = key.to_s.downcase
        methods << key_s if HTTP_METHODS.includes?(key_s)
      end
    end

    private def lookup_case_insensitive(h : Hash(YAML::Any, YAML::Any)?, key : String) : YAML::Any?
      return unless h

      h.each do |candidate_key, value|
        return value if candidate_key.to_s.downcase == key.downcase
      end

      nil
    end

    private def collect_child_resource_keys(h : Hash(YAML::Any, YAML::Any)?, keys : Set(String), allow_templates : Bool)
      return unless h

      h.each_key do |key|
        key_s = key.to_s
        next unless key_s.starts_with?("/")
        next if !allow_templates && key_s.includes?("<<")
        keys << key_s
      end
    end

    private def collect_trait_refs(node : YAML::Any?, refs : Array(YAML::Any))
      return unless node

      if list = node.as_a?
        list.each { |item| refs << item }
      else
        refs << node
      end
    end

    private def apply_trait(trait_ref : YAML::Any, default_media : Array(String), types : YAML::Any, schemas : YAML::Any, traits : YAML::Any, params : Array(Param), definitions_dir : String)
      if trait_node = trait_node_for(trait_ref, traits, definitions_dir)
        extract_operation_params(trait_node[:node], default_media, types, schemas, params, trait_node[:source_dir], definitions_dir)
      end
    end

    private def trait_node_for(trait_ref : YAML::Any, traits : YAML::Any, source_dir : String) : ResolvedNode?
      name = named_ref_name(trait_ref)
      return if name.empty?

      lookup_named_node(traits, name, source_dir)
    end

    private def resource_type_node(resource_h : Hash(YAML::Any, YAML::Any), resource_types : YAML::Any, source_dir : String) : ResolvedNode?
      type_ref = resource_h[YAML::Any.new("type")]?
      return unless type_ref

      name = named_ref_name(type_ref)
      return if name.empty?

      node = lookup_named_node(resource_types, name, source_dir)
      node
    end

    private def named_ref_name(node : YAML::Any) : String
      if s = node.as_s?
        return s
      end

      if h = node.as_h?
        first_key = h.keys.first?
        return first_key.to_s if first_key
      end

      ""
    end

    private def lookup_named_node(collection : YAML::Any, name : String, source_dir : String) : ResolvedNode?
      clean_name = name.split(".").last

      if h = collection.as_h?
        if node = h[YAML::Any.new(clean_name)]?
          return resolve_include(node, source_dir)
        end
      end

      if list = collection.as_a?
        list.each do |item|
          next unless item_h = item.as_h?
          if node = item_h[YAML::Any.new(clean_name)]?
            return resolve_include(node, source_dir)
          end
        end
      end

      nil
    end

    private def lookup_schema_definition(type_name : String, types : YAML::Any, schemas : YAML::Any, seen : Set(String), source_dir : String) : ResolvedNode?
      clean_name = type_name.strip
      clean_name = clean_name[0...-2] if clean_name.ends_with?("[]")
      return if clean_name.empty? || seen.includes?(clean_name)

      seen << clean_name
      lookup_schema_in_collection(types, clean_name, source_dir) || lookup_schema_in_collection(schemas, clean_name, source_dir)
    end

    private def lookup_schema_in_collection(collection : YAML::Any, name : String, source_dir : String) : ResolvedNode?
      if h = collection.as_h?
        if node = h[YAML::Any.new(name)]?
          return resolve_include(node, source_dir)
        end
      end

      if list = collection.as_a?
        list.each do |item|
          next unless item_h = item.as_h?
          if node = item_h[YAML::Any.new(name)]?
            return resolve_include(node, source_dir)
          end
        end
      end

      nil
    end

    private def resolve_include(node : YAML::Any, source_dir : String) : ResolvedNode
      include_path = node.as_s?
      return {node: node, source_dir: source_dir} unless include_path
      return {node: node, source_dir: source_dir} unless include_candidate?(include_path)

      expanded = File.expand_path(include_path, source_dir)
      return {node: node, source_dir: source_dir} unless File.exists?(expanded)

      {
        node:       YAML.parse(File.read(expanded, encoding: "utf-8", invalid: :skip)),
        source_dir: File.dirname(expanded),
      }
    rescue
      {node: node, source_dir: source_dir}
    end

    private def include_candidate?(path : String) : Bool
      return false if path.includes?("\n")
      return false if path.starts_with?("#")

      ext = File.extname(path).downcase
      INCLUDE_EXTENSIONS.includes?(ext)
    end

    private def media_types_from(node : YAML::Any?) : Array(String)
      return ["application/json"] unless node

      if list = node.as_a?
        media_types = list.map(&.to_s)
        return media_types.empty? ? ["application/json"] : media_types
      end

      [node.to_s]
    end
  end
end
