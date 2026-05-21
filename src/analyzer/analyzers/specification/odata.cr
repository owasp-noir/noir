require "xml"
require "../../../models/analyzer"

module Analyzer::Specification
  # OData CSDL (`$metadata`) describes a service's entity sets,
  # singletons, and function/action imports. We turn each of those
  # into the standard URL conventions a real client would call. The
  # base path is left implicit (`/`) because CSDL doesn't carry the
  # service root — downstream consumers prefix it from their own
  # context.
  class OData < Analyzer
    EDM_PRIMITIVE_BODY_TYPES = {
      "Edm.String"         => "string",
      "Edm.Boolean"        => "boolean",
      "Edm.Int16"          => "int",
      "Edm.Int32"          => "int",
      "Edm.Int64"          => "int",
      "Edm.Decimal"        => "number",
      "Edm.Double"         => "number",
      "Edm.Single"         => "number",
      "Edm.Byte"           => "int",
      "Edm.SByte"          => "int",
      "Edm.Guid"           => "string",
      "Edm.DateTime"       => "string",
      "Edm.Date"           => "string",
      "Edm.TimeOfDay"      => "string",
      "Edm.DateTimeOffset" => "string",
      "Edm.Duration"       => "string",
      "Edm.Binary"         => "string",
    }

    alias EntityType = NamedTuple(properties: Array(NamedTuple(name: String, type: String)), keys: Array(String))
    alias Operation = NamedTuple(parameters: Array(NamedTuple(name: String, type: String)), kind: String)

    def analyze
      locator = CodeLocator.instance
      odata_specs = locator.all("odata-spec")
      return @result unless odata_specs.is_a?(Array(String))

      odata_specs.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          parse_metadata(content, path)
        rescue e
          @logger.debug "Failed to parse OData metadata #{path}: #{e.message}"
          @logger.debug_sub e
        end
      end

      @result
    end

    # Single CSDL pass: collect schema-scoped types and operations
    # first (because EntitySet / Singleton / *Import all reference
    # them by qualified name) and then walk every EntityContainer
    # to emit endpoints.
    private def parse_metadata(content : String, source : String)
      doc = XML.parse(content)
      edmx = find_child(doc, "Edmx")
      return unless edmx

      data_services = find_child(edmx, "DataServices")
      return unless data_services

      entity_types = {} of String => EntityType
      operations = {} of String => Operation
      containers = [] of XML::Node

      each_child(data_services, "Schema") do |schema|
        ns = schema["Namespace"]?
        next unless ns

        each_child(schema, "EntityType") do |et|
          name = et["Name"]?
          next unless name
          entity_types["#{ns}.#{name}"] = collect_entity_type(et)
        end

        each_child(schema, "Function") do |fn|
          name = fn["Name"]?
          next unless name
          # Multiple `Function` elements can share a name (overloads);
          # downstream emit uses the import-side name anyway, so we
          # last-wins here.
          operations["#{ns}.#{name}"] = collect_operation(fn, "function")
        end

        each_child(schema, "Action") do |act|
          name = act["Name"]?
          next unless name
          operations["#{ns}.#{name}"] = collect_operation(act, "action")
        end

        each_child(schema, "EntityContainer") do |container|
          containers << container
        end
      end

      containers.each do |container|
        emit_container(container, source, entity_types, operations)
      end
    end

    private def collect_entity_type(node : XML::Node) : EntityType
      properties = [] of NamedTuple(name: String, type: String)
      keys = [] of String

      if key_node = find_child(node, "Key")
        each_child(key_node, "PropertyRef") do |pr|
          if name = pr["Name"]?
            keys << name
          end
        end
      end

      each_child(node, "Property") do |prop|
        next unless name = prop["Name"]?
        type = prop["Type"]? || "Edm.String"
        properties << {name: name, type: type}
      end

      {properties: properties, keys: keys}
    end

    private def collect_operation(node : XML::Node, kind : String) : Operation
      parameters = [] of NamedTuple(name: String, type: String)
      each_child(node, "Parameter") do |p|
        next unless name = p["Name"]?
        # OData binds the first Parameter of a bound operation to the
        # entity itself (`Name="bindingParameter"` by convention) —
        # not something a caller passes in the body. The Import side
        # is what surfaces unbound callable shapes, so we keep all
        # parameters here and let the emit pass decide what to do
        # with the binding parameter when it sees `IsBound="true"`.
        type = p["Type"]? || "Edm.String"
        parameters << {name: name, type: type}
      end
      {parameters: parameters, kind: kind}
    end

    private def emit_container(container : XML::Node, source : String,
                               entity_types : Hash(String, EntityType),
                               operations : Hash(String, Operation))
      each_child(container, "EntitySet") do |es|
        emit_entity_set(es, source, entity_types)
      end

      each_child(container, "Singleton") do |s|
        emit_singleton(s, source, entity_types)
      end

      each_child(container, "FunctionImport") do |fi|
        emit_function_import(fi, source, operations)
      end

      each_child(container, "ActionImport") do |ai|
        emit_action_import(ai, source, operations)
      end
    end

    # EntitySet → the five-verb CRUD shape from the URL conventions.
    # The collection-level path lists/creates, the keyed path
    # reads/updates/deletes. The keyed-update verb in OData is
    # `PATCH` (deltas); `PUT` is the full-replacement alternative
    # and is not emitted to keep the surface minimal.
    private def emit_entity_set(node : XML::Node, source : String,
                                entity_types : Hash(String, EntityType))
      name = node["Name"]?
      return unless name

      type_ref = node["EntityType"]?
      entity = type_ref ? entity_types[type_ref]? : nil

      list_params = query_option_params
      keyed_params = [Param.new("key", "", "path")]

      body_params = entity ? entity_body_params(entity) : [] of Param

      details = Details.new(PathInfo.new(source))
      base_url = "/#{name}"
      keyed_url = "/#{name}({key})"

      emit_endpoint(base_url, "GET", list_params.dup, details, "entityset-list", name)
      emit_endpoint(base_url, "POST", body_params.dup, details, "entityset-create", name)
      emit_endpoint(keyed_url, "GET", keyed_params.dup, details, "entityset-read", name)
      emit_endpoint(keyed_url, "PATCH", keyed_params + body_params, details, "entityset-update", name)
      emit_endpoint(keyed_url, "DELETE", keyed_params.dup, details, "entityset-delete", name)
    end

    # Singleton → a single resource. No collection-level verbs and
    # no key segment; PATCH writes deltas the same way EntitySet
    # does.
    private def emit_singleton(node : XML::Node, source : String,
                               entity_types : Hash(String, EntityType))
      name = node["Name"]?
      return unless name

      type_ref = node["Type"]?
      entity = type_ref ? entity_types[type_ref]? : nil
      body_params = entity ? entity_body_params(entity) : [] of Param

      details = Details.new(PathInfo.new(source))
      url = "/#{name}"

      emit_endpoint(url, "GET", [] of Param, details, "singleton-read", name)
      emit_endpoint(url, "PATCH", body_params, details, "singleton-update", name)
    end

    # Function imports are read-only and parameter-bearing — OData's
    # URL convention is to inline parameters into the path:
    # `/GetTopProducts(count=5)`. We surface each parameter as a
    # path param so DAST consumers know they're addressable.
    private def emit_function_import(node : XML::Node, source : String,
                                     operations : Hash(String, Operation))
      name = node["Name"]?
      return unless name
      fn_ref = node["Function"]?
      operation = fn_ref ? operations[fn_ref]? : nil

      params = [] of Param
      if operation
        operation[:parameters].each do |p|
          params << Param.new(p[:name], "", "path")
        end
      end

      url = function_url(name, operation)
      details = Details.new(PathInfo.new(source))
      emit_endpoint(url, "GET", params, details, "function-import", name)
    end

    # Action imports are POST and carry their parameters as a JSON
    # body, per the OData v4 binding spec.
    private def emit_action_import(node : XML::Node, source : String,
                                   operations : Hash(String, Operation))
      name = node["Name"]?
      return unless name
      action_ref = node["Action"]?
      operation = action_ref ? operations[action_ref]? : nil

      params = [] of Param
      if operation
        operation[:parameters].each do |p|
          params << Param.new(p[:name], "", "json")
        end
      end

      details = Details.new(PathInfo.new(source))
      emit_endpoint("/#{name}", "POST", params, details, "action-import", name)
    end

    private def function_url(name : String, operation : Operation?) : String
      return "/#{name}()" if operation.nil? || operation[:parameters].empty?
      args = operation[:parameters].map { |p| "#{p[:name]}={#{p[:name]}}" }.join(",")
      "/#{name}(#{args})"
    end

    # Standard OData v4 system query options. Emitting them as
    # `query` params keeps them addressable in DAST tooling without
    # claiming any particular value space.
    private def query_option_params : Array(Param)
      ["$filter", "$select", "$expand", "$top", "$skip", "$orderby", "$count", "$search"].map do |opt|
        Param.new(opt, "", "query")
      end
    end

    private def entity_body_params(entity : EntityType) : Array(Param)
      entity[:properties].map do |prop|
        hint = EDM_PRIMITIVE_BODY_TYPES[prop[:type]]?
        Param.new(prop[:name], hint || "", "json")
      end
    end

    private def emit_endpoint(url : String, method : String, params : Array(Param),
                              details : Details, op_kind : String, op_name : String)
      endpoint = Endpoint.new(url, method, params, details)
      endpoint.add_tag(Tag.new("odata", "#{op_kind}:#{op_name}", "odata_analyzer"))
      @result << endpoint
    end

    private def find_child(node : XML::Node, local_name : String) : XML::Node?
      node.children.each do |c|
        return c if c.element? && c.name == local_name
      end
      nil
    end

    private def each_child(node : XML::Node, local_name : String, &)
      node.children.each do |c|
        yield c if c.element? && c.name == local_name
      end
    end
  end
end
