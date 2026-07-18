require "../../../models/analyzer"
require "../../../miniparsers/js_object_config_extractor"
require "./schema_api_common"

module Analyzer::Specification
  # Strapi turns every content type into REST routes under `/api`:
  # a collection type gets the five-verb CRUD shape on its plural name,
  # a single type gets read/update/delete on its singular name.
  #
  # Custom routes declared in `src/api/<name>/routes/*.{ts,js}` are read
  # separately and mounted under the same `/api` prefix.
  class Strapi < Analyzer
    include SchemaApiCommon

    ATTRIBUTE_TYPE_HINTS = {
      "string"      => "string",
      "text"        => "string",
      "richtext"    => "string",
      "email"       => "string",
      "password"    => "string",
      "uid"         => "string",
      "enumeration" => "string",
      "integer"     => "int",
      "biginteger"  => "int",
      "float"       => "number",
      "decimal"     => "number",
      "boolean"     => "boolean",
      "date"        => "datetime",
      "datetime"    => "datetime",
      "time"        => "datetime",
      "timestamp"   => "datetime",
      "json"        => "object",
    }

    # Relations, components, dynamic zones and media are not scalar body
    # fields - they take nested reference payloads rather than a value.
    NON_SCALAR_TYPES = {"relation", "component", "dynamiczone", "media"}

    MAX_FILTER_PARAMS = 25

    API_PREFIX = "/api"
    TAG_SOURCE = "strapi_analyzer"

    def analyze
      locator = CodeLocator.instance

      schemas = locator.all("strapi-schema")
      if schemas.is_a?(Array(String))
        schemas.each do |path|
          next unless File.exists?(path)
          begin
            parse_schema(read_file_content(path), path)
          rescue e
            @logger.debug "Failed to parse Strapi schema #{path}"
            @logger.debug_sub e
          end
        end
      end

      routes = locator.all("strapi-routes")
      if routes.is_a?(Array(String))
        routes.each do |path|
          next unless File.exists?(path)
          begin
            parse_routes(read_file_content(path), path)
          rescue e
            @logger.debug "Failed to parse Strapi routes #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    private def parse_schema(content : String, source : String)
      root = JSON.parse(content).as_h?
      return unless root

      kind = root["kind"]?.try(&.as_s?)
      return unless kind

      # A content type opted out of the content API has no REST surface.
      if plugin_options = root["pluginOptions"]?.try(&.as_h?)
        if content_api = plugin_options["content-api"]?.try(&.as_h?)
          return if content_api["enabled"]?.try(&.as_bool?) == false
        end
      end

      info = root["info"]?.try(&.as_h?)
      return unless info

      attributes = root["attributes"]?.try(&.as_h?)
      details = Details.new(PathInfo.new(source))

      case kind
      when "collectionType"
        name = info["pluralName"]?.try(&.as_s?) ||
               root["collectionName"]?.try(&.as_s?) ||
               api_directory_name(source)
        return unless name
        emit_collection_type(name, attributes, details)
      when "singleType"
        name = info["singularName"]?.try(&.as_s?) || api_directory_name(source)
        return unless name
        emit_single_type(name, attributes, details)
      end
    end

    private def emit_collection_type(name : String, attributes : Hash(String, JSON::Any)?, details : Details)
      collection_url = "#{API_PREFIX}/#{name}"
      # Strapi 5 addresses documents by documentId. Strapi 4 used a
      # numeric id at the same position; the schema files are identical
      # between the two, so we emit the current form and note the other.
      item_url = "#{collection_url}/{documentId}"

      body_params = attribute_body_params(attributes)
      list_params = global_query_params + filter_params(attributes)

      list = emit(@result, collection_url, "GET", list_params, details, "strapi", "collection-list:#{name}", TAG_SOURCE)
      note_v4_addressing(list)
      emit(@result, collection_url, "POST", body_params.dup, details, "strapi", "collection-create:#{name}", TAG_SOURCE)

      read = emit(@result, item_url, "GET", global_query_params, details, "strapi", "collection-read:#{name}", TAG_SOURCE)
      note_v4_addressing(read)
      emit(@result, item_url, "PUT", body_params.dup, details, "strapi", "collection-update:#{name}", TAG_SOURCE)
      emit(@result, item_url, "DELETE", [] of Param, details, "strapi", "collection-delete:#{name}", TAG_SOURCE)
    end

    private def emit_single_type(name : String, attributes : Hash(String, JSON::Any)?, details : Details)
      url = "#{API_PREFIX}/#{name}"
      body_params = attribute_body_params(attributes)

      emit(@result, url, "GET", global_query_params, details, "strapi", "single-read:#{name}", TAG_SOURCE)
      emit(@result, url, "PUT", body_params.dup, details, "strapi", "single-update:#{name}", TAG_SOURCE)
      emit(@result, url, "DELETE", [] of Param, details, "strapi", "single-delete:#{name}", TAG_SOURCE)
    end

    private def note_v4_addressing(endpoint : Endpoint)
      endpoint.add_tag(Tag.new("strapi-note", "Strapi v4 addresses documents by {id} instead of {documentId}", TAG_SOURCE))
    end

    # Strapi's REST query vocabulary. A bare attribute name is not a
    # valid query key - filtering goes through `?filters[<f>][$eq]=`.
    private def global_query_params : Array(Param)
      ["populate", "fields", "sort", "locale", "status", "pagination[page]", "pagination[pageSize]"].map do |name|
        Param.new(name, "", "query")
      end
    end

    private def filter_params(attributes : Hash(String, JSON::Any)?) : Array(Param)
      params = [] of Param
      return params unless attributes

      attributes.each do |name, definition|
        break if params.size >= MAX_FILTER_PARAMS
        next unless scalar_attribute?(definition)
        push_param_once(params, Param.new("filters[#{name}][$eq]", "", "query"))
      end

      params
    end

    # Strapi wraps the payload in a `data` envelope, so the wire name of
    # an attribute is `data.<name>`.
    private def attribute_body_params(attributes : Hash(String, JSON::Any)?) : Array(Param)
      params = [] of Param
      return params unless attributes

      attributes.each do |name, definition|
        next unless scalar_attribute?(definition)
        hint = type_hint(definition.as_h?.try(&.["type"]?).try(&.as_s?) || "", ATTRIBUTE_TYPE_HINTS)
        push_param_once(params, Param.new("data.#{name}", hint, "json"))
      end

      params
    end

    private def scalar_attribute?(definition : JSON::Any) : Bool
      attribute = definition.as_h?
      return false unless attribute
      type = attribute["type"]?.try(&.as_s?)
      return false unless type
      !NON_SCALAR_TYPES.includes?(type)
    end

    # `src/api/<name>/content-types/<name>/schema.json` -> `<name>`.
    private def api_directory_name(source : String) : String?
      path = source.includes?('\\') ? source.gsub('\\', '/') : source
      marker = path.index("/api/")
      return unless marker
      rest = path[(marker + 5)..]
      segment = rest.split('/').first?
      return if segment.nil? || segment.empty?
      segment
    end

    private def parse_routes(content : String, source : String)
      configs = Noir::JSObjectConfigExtractor.extract(content, ["routes"])
      return if configs.empty?

      configs.each do |config|
        entries = config.array("routes")
        next unless entries

        entries.each do |entry|
          next unless entry.is_a?(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))

          method = entry["method"]?
          path = entry["path"]?
          next unless method.is_a?(String) && path.is_a?(String)
          next if path.empty?

          url = join_path(API_PREFIX, normalize_colon_path(path))
          details = Details.new(PathInfo.new(source, config.line))
          handler = entry["handler"]?
          label = handler.is_a?(String) ? handler : path

          emit(@result, url, method.upcase, [] of Param, details, "strapi", "custom-route:#{label}", TAG_SOURCE)
        end
      end
    end
  end
end
