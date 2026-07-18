require "../../../models/analyzer"
require "../../../utils/yaml"
require "./schema_api_common"

module Analyzer::Specification
  # Directus serves every user collection in the snapshot at
  # `/items/<collection>`, with the item-level verbs on
  # `/items/<collection>/<id>` and singletons on
  # `/items/<collection>/singleton`.
  class Directus < Analyzer
    include SchemaApiCommon

    FIELD_TYPE_HINTS = {
      "string"     => "string",
      "text"       => "string",
      "uuid"       => "string",
      "hash"       => "string",
      "csv"        => "array",
      "json"       => "object",
      "integer"    => "int",
      "biginteger" => "int",
      "float"      => "number",
      "decimal"    => "number",
      "boolean"    => "boolean",
      "datetime"   => "datetime",
      "date"       => "datetime",
      "time"       => "datetime",
      "timestamp"  => "datetime",
    }

    # Relational and presentational fields are not columns - they carry
    # no writable value on the item itself.
    NON_DATA_SPECIALS = {"alias", "no-data", "o2m", "m2m", "m2a", "group", "translations", "files"}

    # Directus' system tables are always present and are not part of the
    # project's own surface.
    SYSTEM_PREFIX = "directus_"

    # A wide collection would otherwise contribute hundreds of filter
    # params to a single endpoint.
    MAX_FILTER_PARAMS = 25

    TAG_SOURCE = "directus_analyzer"

    def analyze
      locator = CodeLocator.instance
      snapshots = locator.all("directus-snapshot")
      return @result unless snapshots.is_a?(Array(String))

      snapshots.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          parse_snapshot(content, path)
        rescue e
          @logger.debug "Failed to parse Directus snapshot #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def parse_snapshot(content : String, source : String)
      root = parse_yaml(content).as_h?
      return unless root

      collections = root[YAML::Any.new("collections")]?.try(&.as_a?)
      return unless collections

      fields_by_collection = group_fields(root[YAML::Any.new("fields")]?)
      details = Details.new(PathInfo.new(source))

      collections.each do |entry|
        collection = entry.as_h?
        next unless collection

        name = collection[YAML::Any.new("collection")]?.try(&.as_s?)
        next unless name
        next if name.starts_with?(SYSTEM_PREFIX)

        # A collection with a null `schema` is a folder used only for
        # grouping in the admin UI. It has no table and no items route.
        next if collection.has_key?(YAML::Any.new("schema")) && collection[YAML::Any.new("schema")].raw.nil?

        meta = collection[YAML::Any.new("meta")]?.try(&.as_h?)
        singleton = meta.try { |m| m[YAML::Any.new("singleton")]?.try(&.as_bool?) } || false

        emit_collection(name, fields_by_collection[name]? || [] of YAML::Any, singleton, details)
      end
    end

    private def group_fields(node : YAML::Any?) : Hash(String, Array(YAML::Any))
      grouped = Hash(String, Array(YAML::Any)).new
      entries = node.try(&.as_a?)
      return grouped unless entries

      entries.each do |entry|
        field = entry.as_h?
        next unless field
        collection = field[YAML::Any.new("collection")]?.try(&.as_s?)
        next unless collection
        (grouped[collection] ||= [] of YAML::Any) << entry
      end

      grouped
    end

    private def emit_collection(name : String, fields : Array(YAML::Any),
                                singleton : Bool, details : Details)
      body_params = field_body_params(fields)

      if singleton
        # A singleton has one implicit row, so there is no collection
        # listing and no id segment.
        url = "/items/#{name}/singleton"
        emit(@result, url, "GET", global_query_params, details, "directus", "singleton-read:#{name}", TAG_SOURCE)
        emit(@result, url, "PATCH", body_params.dup, details, "directus", "singleton-update:#{name}", TAG_SOURCE)
        return
      end

      collection_url = "/items/#{name}"
      item_url = "#{collection_url}/{id}"
      list_params = global_query_params + filter_params(fields)

      emit(@result, collection_url, "GET", list_params, details, "directus", "collection-list:#{name}", TAG_SOURCE)
      emit(@result, collection_url, "POST", body_params.dup, details, "directus", "collection-create:#{name}", TAG_SOURCE)
      # Batch write verbs take the key set in the body rather than in the path.
      emit(@result, collection_url, "PATCH", batch_params(body_params), details, "directus", "collection-update-batch:#{name}", TAG_SOURCE)
      emit(@result, collection_url, "DELETE", [Param.new("keys", "array", "json")], details, "directus", "collection-delete-batch:#{name}", TAG_SOURCE)
      emit(@result, item_url, "GET", global_query_params, details, "directus", "item-read:#{name}", TAG_SOURCE)
      emit(@result, item_url, "PATCH", body_params.dup, details, "directus", "item-update:#{name}", TAG_SOURCE)
      emit(@result, item_url, "DELETE", [] of Param, details, "directus", "item-delete:#{name}", TAG_SOURCE)
    end

    # Directus' global query parameters, valid on every read endpoint.
    private def global_query_params : Array(Param)
      ["fields", "filter", "search", "sort", "limit", "offset", "page", "deep", "meta", "aggregate"].map do |name|
        Param.new(name, "", "query")
      end
    end

    # A bare field name is not a Directus query key - filtering goes
    # through `?filter[<field>][_eq]=`. Emitting the wire-accurate form
    # keeps the params replayable.
    private def filter_params(fields : Array(YAML::Any)) : Array(Param)
      params = [] of Param

      fields.each do |entry|
        break if params.size >= MAX_FILTER_PARAMS
        field = entry.as_h?
        next unless field
        # Readonly is deliberately not excluded here: `id`, `date_created`
        # and friends cannot be written but are entirely filterable, and
        # they are among the most useful filters to know about.
        next unless filterable_field?(field)
        name = field[YAML::Any.new("field")]?.try(&.as_s?)
        next unless name
        push_param_once(params, Param.new("filter[#{name}][_eq]", "", "query"))
      end

      params
    end

    private def field_body_params(fields : Array(YAML::Any)) : Array(Param)
      params = [] of Param

      fields.each do |entry|
        field = entry.as_h?
        next unless field
        next unless writable_field?(field)
        name = field[YAML::Any.new("field")]?.try(&.as_s?)
        next unless name

        # An auto-increment primary key is assigned by the database.
        schema = field[YAML::Any.new("schema")]?.try(&.as_h?)
        next if schema.try { |s| s[YAML::Any.new("has_auto_increment")]?.try(&.as_bool?) }

        hint = type_hint(field[YAML::Any.new("type")]?.try(&.as_s?) || "", FIELD_TYPE_HINTS)
        push_param_once(params, Param.new(name, hint, "json"))
      end

      params
    end

    # Backs a real column, so it can appear in a filter expression.
    private def filterable_field?(field : Hash(YAML::Any, YAML::Any)) : Bool
      meta = field[YAML::Any.new("meta")]?.try(&.as_h?)
      return true unless meta

      if specials = meta[YAML::Any.new("special")]?.try(&.as_a?)
        return false if specials.any? do |special|
                          value = special.as_s?
                          value ? NON_DATA_SPECIALS.includes?(value) : false
                        end
      end

      true
    end

    # Accepts a value on write. Strictly narrower than `filterable_field?`.
    private def writable_field?(field : Hash(YAML::Any, YAML::Any)) : Bool
      return false unless filterable_field?(field)

      meta = field[YAML::Any.new("meta")]?.try(&.as_h?)
      return true unless meta

      !meta[YAML::Any.new("readonly")]?.try(&.as_bool?)
    end

    # The batch update endpoint takes `{ keys: [...], data: {...} }`, so
    # the field params are nested under `data`.
    private def batch_params(body_params : Array(Param)) : Array(Param)
      params = [Param.new("keys", "array", "json")]
      body_params.each do |param|
        push_param_once(params, Param.new("data.#{param.name}", param.value, "json"))
      end
      params
    end
  end
end
