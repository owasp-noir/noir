require "../../../models/analyzer"
require "../../../miniparsers/js_object_config_extractor"
require "./schema_api_common"

module Analyzer::Specification
  # Payload CMS mounts every collection at `/api/<slug>` and every global
  # at `/api/globals/<slug>`, generating the CRUD verbs plus auth and
  # version route families from flags on the config.
  class PayloadCms < Analyzer
    include SchemaApiCommon

    FIELD_TYPE_HINTS = {
      "text"         => "string",
      "textarea"     => "string",
      "email"        => "string",
      "code"         => "string",
      "richtext"     => "string",
      "select"       => "string",
      "radio"        => "string",
      "relationship" => "string",
      "upload"       => "string",
      "number"       => "number",
      "checkbox"     => "boolean",
      "date"         => "datetime",
      "json"         => "object",
      "group"        => "object",
      "point"        => "array",
      "array"        => "array",
      "blocks"       => "array",
    }

    # Layout-only field types carry no `name`; their children belong to
    # the parent document. Most real configs wrap fields in these, so
    # hoisting is what makes the body params correct.
    PRESENTATIONAL_TYPES = {"row", "collapsible", "ui"}

    # These do carry a `name` and nest their children under it.
    NESTING_TYPES = {"group", "array", "blocks"}

    # Matches graphql_sdl_parser's nesting cap.
    MAX_FIELD_DEPTH   =  2
    MAX_FILTER_PARAMS = 25

    DEFAULT_API_PREFIX = "/api"
    TAG_SOURCE         = "payload_cms_analyzer"

    def analyze
      locator = CodeLocator.instance

      api_prefix = resolve_api_prefix(locator.all("payload-config"))

      collections = locator.all("payload-collection")
      if collections.is_a?(Array(String))
        collections.each do |path|
          next unless File.exists?(path)
          begin
            parse_collections(read_file_content(path), path, api_prefix)
          rescue e
            @logger.debug "Failed to parse Payload collection #{path}"
            @logger.debug_sub e
          end
        end
      end

      globals = locator.all("payload-global")
      if globals.is_a?(Array(String))
        globals.each do |path|
          next unless File.exists?(path)
          begin
            parse_globals(read_file_content(path), path, api_prefix)
          rescue e
            @logger.debug "Failed to parse Payload global #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    # `buildConfig({ routes: { api: '/custom' } })` relocates the whole
    # REST mount, so it has to be resolved before any endpoint is built.
    private def resolve_api_prefix(configs) : String
      return DEFAULT_API_PREFIX unless configs.is_a?(Array(String))

      configs.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          Noir::JSObjectConfigExtractor.extract(content, ["routes"]).each do |config|
            routes = config.hash("routes")
            next unless routes
            api = routes["api"]?
            return api if api.is_a?(String) && !api.empty?
          end
        rescue e
          @logger.debug "Failed to read Payload config #{path}"
          @logger.debug_sub e
        end
      end

      DEFAULT_API_PREFIX
    end

    private def parse_collections(content : String, source : String, api_prefix : String)
      Noir::JSObjectConfigExtractor.extract(content, ["slug", "fields"]).each do |config|
        slug = config.string("slug")
        next if slug.nil? || slug.empty?

        details = Details.new(PathInfo.new(source, config.line))
        body_params = field_params(config.array("fields"))
        base = join_path(api_prefix, slug)

        emit_collection(base, slug, body_params, config, details)
        emit_auth_routes(base, slug, details) if config.truthy?("auth")
        emit_version_routes(base, slug, details) if config.truthy?("versions")
        emit_custom_endpoints(base, slug, config, details)
      end
    end

    private def emit_collection(base : String, slug : String, body_params : Array(Param),
                                config : Noir::JSObjectConfigExtractor::ConfigObject, details : Details)
      item_url = "#{base}/{id}"
      list_params = global_query_params + filter_params(config.array("fields"))

      emit(@result, base, "GET", list_params, details, "payload", "collection-list:#{slug}", TAG_SOURCE)
      emit(@result, base, "POST", body_params.dup, details, "payload", "collection-create:#{slug}", TAG_SOURCE)
      # The bulk write verbs select their targets with ?where=.
      emit(@result, base, "PATCH", body_params + [Param.new("where", "", "query")], details, "payload", "collection-update-bulk:#{slug}", TAG_SOURCE)
      emit(@result, base, "DELETE", [Param.new("where", "", "query")], details, "payload", "collection-delete-bulk:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/count", "GET", [Param.new("where", "", "query")], details, "payload", "collection-count:#{slug}", TAG_SOURCE)
      emit(@result, item_url, "GET", global_query_params, details, "payload", "collection-read:#{slug}", TAG_SOURCE)
      emit(@result, item_url, "PATCH", body_params.dup, details, "payload", "collection-update:#{slug}", TAG_SOURCE)
      emit(@result, item_url, "DELETE", [] of Param, details, "payload", "collection-delete:#{slug}", TAG_SOURCE)
    end

    # An auth-enabled collection gets the whole credential surface, which
    # is the most security-relevant part of a Payload app.
    private def emit_auth_routes(base : String, slug : String, details : Details)
      credentials = [
        Param.new("email", "string", "json"),
        Param.new("password", "string", "json"),
      ]

      emit(@result, "#{base}/login", "POST", credentials.dup, details, "payload", "auth-login:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/logout", "POST", [] of Param, details, "payload", "auth-logout:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/refresh-token", "POST", [] of Param, details, "payload", "auth-refresh:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/me", "GET", [] of Param, details, "payload", "auth-me:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/forgot-password", "POST", [Param.new("email", "string", "json")], details, "payload", "auth-forgot-password:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/reset-password", "POST", [
        Param.new("token", "string", "json"),
        Param.new("password", "string", "json"),
      ], details, "payload", "auth-reset-password:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/unlock", "POST", [Param.new("email", "string", "json")], details, "payload", "auth-unlock:#{slug}", TAG_SOURCE)
    end

    private def emit_version_routes(base : String, slug : String, details : Details)
      emit(@result, "#{base}/versions", "GET", global_query_params, details, "payload", "versions-list:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/versions/{id}", "GET", [] of Param, details, "payload", "versions-read:#{slug}", TAG_SOURCE)
      emit(@result, "#{base}/versions/{id}", "POST", [] of Param, details, "payload", "versions-restore:#{slug}", TAG_SOURCE)
    end

    private def emit_custom_endpoints(base : String, slug : String,
                                      config : Noir::JSObjectConfigExtractor::ConfigObject, details : Details)
      entries = config.array("endpoints")
      return unless entries

      entries.each do |entry|
        next unless entry.is_a?(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))
        path = entry["path"]?
        method = entry["method"]?
        next unless path.is_a?(String) && method.is_a?(String)

        url = join_path(base, normalize_colon_path(path))
        emit(@result, url, method.upcase, [] of Param, details, "payload", "custom-endpoint:#{slug}", TAG_SOURCE)
      end
    end

    private def parse_globals(content : String, source : String, api_prefix : String)
      Noir::JSObjectConfigExtractor.extract(content, ["slug", "fields"]).each do |config|
        slug = config.string("slug")
        next if slug.nil? || slug.empty?

        details = Details.new(PathInfo.new(source, config.line))
        body_params = field_params(config.array("fields"))
        url = join_path(join_path(api_prefix, "globals"), slug)

        emit(@result, url, "GET", global_query_params, details, "payload", "global-read:#{slug}", TAG_SOURCE)
        # Globals are updated with POST, not PATCH.
        emit(@result, url, "POST", body_params, details, "payload", "global-update:#{slug}", TAG_SOURCE)
        emit_custom_endpoints(url, slug, config, details)
      end
    end

    private def global_query_params : Array(Param)
      ["depth", "limit", "page", "sort", "where", "locale", "draft", "select", "populate"].map do |name|
        Param.new(name, "", "query")
      end
    end

    # Payload filters through `?where[<field>][equals]=`; the bare field
    # name is not a query key.
    private def filter_params(fields : Array(Noir::JSObjectConfigExtractor::ConfigValue)?) : Array(Param)
      params = [] of Param
      field_params(fields).each do |param|
        break if params.size >= MAX_FILTER_PARAMS
        push_param_once(params, Param.new("where[#{param.name}][equals]", "", "query"))
      end
      params
    end

    private def field_params(fields : Array(Noir::JSObjectConfigExtractor::ConfigValue)?) : Array(Param)
      params = [] of Param
      return params unless fields
      collect_fields(fields, "", 0, params)
      params
    end

    private def collect_fields(fields : Array(Noir::JSObjectConfigExtractor::ConfigValue), prefix : String,
                               depth : Int32, sink : Array(Param))
      return if depth > MAX_FIELD_DEPTH

      fields.each do |entry|
        next unless entry.is_a?(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))

        type_value = entry["type"]?
        type = type_value.is_a?(String) ? type_value.downcase : ""
        name_value = entry["name"]?
        name = name_value.is_a?(String) ? name_value : nil

        # Layout wrappers have no name: their children sit at the parent
        # level in the stored document.
        if PRESENTATIONAL_TYPES.includes?(type)
          nested = entry["fields"]?
          collect_fields(nested, prefix, depth, sink) if nested.is_a?(Array(Noir::JSObjectConfigExtractor::ConfigValue))
          next
        end

        # Tabs are layout too, except that a *named* tab nests its
        # children under that name.
        if type == "tabs"
          tabs = entry["tabs"]?
          next unless tabs.is_a?(Array(Noir::JSObjectConfigExtractor::ConfigValue))
          tabs.each do |tab|
            next unless tab.is_a?(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))
            tab_fields = tab["fields"]?
            next unless tab_fields.is_a?(Array(Noir::JSObjectConfigExtractor::ConfigValue))
            tab_name = tab["name"]?
            if tab_name.is_a?(String) && !tab_name.empty?
              collect_fields(tab_fields, "#{prefix}#{tab_name}.", depth + 1, sink)
            else
              collect_fields(tab_fields, prefix, depth, sink)
            end
          end
          next
        end

        next if name.nil? || name.empty?
        qualified = "#{prefix}#{name}"

        if NESTING_TYPES.includes?(type)
          push_param_once(sink, Param.new(qualified, type_hint(type, FIELD_TYPE_HINTS), "json"))

          if type == "blocks"
            blocks = entry["blocks"]?
            if blocks.is_a?(Array(Noir::JSObjectConfigExtractor::ConfigValue))
              blocks.each do |block|
                next unless block.is_a?(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))
                block_fields = block["fields"]?
                collect_fields(block_fields, "#{qualified}.", depth + 1, sink) if block_fields.is_a?(Array(Noir::JSObjectConfigExtractor::ConfigValue))
              end
            end
          else
            nested = entry["fields"]?
            collect_fields(nested, "#{qualified}.", depth + 1, sink) if nested.is_a?(Array(Noir::JSObjectConfigExtractor::ConfigValue))
          end
          next
        end

        push_param_once(sink, Param.new(qualified, type_hint(type, FIELD_TYPE_HINTS), "json"))
      end
    end
  end
end
