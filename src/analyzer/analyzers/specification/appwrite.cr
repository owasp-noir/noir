require "../../../models/analyzer"
require "./schema_api_common"

module Analyzer::Specification
  # Appwrite generates its whole REST surface from `appwrite.json`:
  # every declared collection becomes a documents endpoint family,
  # every function an executions family, every bucket a files family.
  #
  # Appwrite 1.6 renamed collections/documents to tables/rows and moved
  # them from `/v1/databases/...` to `/v1/tablesdb/...`. A project uses
  # one naming or the other, so we emit the family matching the keys
  # actually present — emitting both would mean half the output 404s.
  class Appwrite < Analyzer
    include SchemaApiCommon

    ATTRIBUTE_TYPE_HINTS = {
      "string"       => "string",
      "email"        => "string",
      "ip"           => "string",
      "url"          => "string",
      "enum"         => "string",
      "relationship" => "string",
      "integer"      => "int",
      "double"       => "number",
      "boolean"      => "boolean",
      "datetime"     => "datetime",
    }

    TAG_SOURCE = "appwrite_analyzer"

    def analyze
      locator = CodeLocator.instance
      configs = locator.all("appwrite-config")
      return @result unless configs.is_a?(Array(String))

      configs.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          parse_config(content, path)
        rescue e
          @logger.debug "Failed to parse Appwrite config #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def parse_config(content : String, source : String)
      root = JSON.parse(content).as_h?
      return unless root

      project_id = root["projectId"]?.try(&.as_s?) || ""
      details = Details.new(PathInfo.new(source))

      # >=1.6 vocabulary takes precedence when present.
      if tables = root["tables"]?.try(&.as_a?)
        tables.each { |t| emit_data_resource(t, project_id, details, table_style: true) }
      elsif collections = root["collections"]?.try(&.as_a?)
        collections.each { |c| emit_data_resource(c, project_id, details, table_style: false) }
      end

      root["functions"]?.try(&.as_a?).try &.each do |fn|
        emit_function(fn, project_id, details)
      end

      root["buckets"]?.try(&.as_a?).try &.each do |bucket|
        emit_bucket(bucket, project_id, details)
      end
    end

    # Collections (<=1.5) and tables (>=1.6) are the same shape under
    # different names, so one routine emits both with the vocabulary
    # swapped.
    private def emit_data_resource(node : JSON::Any, project_id : String,
                                   details : Details, *, table_style : Bool)
      resource = node.as_h?
      return unless resource

      id = resource["$id"]?.try(&.as_s?)
      return unless id
      database_id = resource["databaseId"]?.try(&.as_s?)
      return unless database_id

      collection_url =
        if table_style
          "/v1/tablesdb/#{database_id}/tables/#{id}/rows"
        else
          "/v1/databases/#{database_id}/collections/#{id}/documents"
        end
      item_key = table_style ? "rowId" : "documentId"
      item_url = "#{collection_url}/{#{item_key}}"
      kind = table_style ? "table" : "collection"

      attribute_key = table_style ? "columns" : "attributes"
      body_params = data_body_params(resource[attribute_key]?)

      list_params = [
        Param.new("queries", "", "query"),
        Param.new("search", "", "query"),
      ] + auth_headers(project_id)

      create_params = [Param.new(item_key, "", "json")] +
                      body_params +
                      [Param.new("permissions", "array", "json")] +
                      auth_headers(project_id)

      update_params = body_params + [Param.new("permissions", "array", "json")] + auth_headers(project_id)

      emit(@result, collection_url, "GET", list_params, details, "appwrite", "#{kind}-list:#{id}", TAG_SOURCE)
      emit(@result, collection_url, "POST", create_params, details, "appwrite", "#{kind}-create:#{id}", TAG_SOURCE)
      emit(@result, item_url, "GET", auth_headers(project_id), details, "appwrite", "#{kind}-read:#{id}", TAG_SOURCE)
      emit(@result, item_url, "PATCH", update_params, details, "appwrite", "#{kind}-update:#{id}", TAG_SOURCE)
      emit(@result, item_url, "DELETE", auth_headers(project_id), details, "appwrite", "#{kind}-delete:#{id}", TAG_SOURCE)
    end

    # Appwrite wraps document/row attributes in a `data` object on
    # write, so the wire name is `data.<key>` rather than the bare key.
    private def data_body_params(node : JSON::Any?) : Array(Param)
      params = [] of Param
      entries = node.try(&.as_a?)
      return params unless entries

      entries.each do |entry|
        attr = entry.as_h?
        next unless attr
        key = attr["key"]?.try(&.as_s?)
        next unless key

        hint =
          if attr["array"]?.try(&.as_bool?)
            "array"
          else
            type_hint(attr["type"]?.try(&.as_s?) || "", ATTRIBUTE_TYPE_HINTS)
          end
        push_param_once(params, Param.new("data.#{key}", hint, "json"))
      end

      params
    end

    private def emit_function(node : JSON::Any, project_id : String, details : Details)
      fn = node.as_h?
      return unless fn
      id = fn["$id"]?.try(&.as_s?)
      return unless id

      base = "/v1/functions/#{id}/executions"
      execute_params = [
        Param.new("body", "string", "json"),
        Param.new("async", "boolean", "json"),
        Param.new("path", "string", "json"),
        Param.new("method", "string", "json"),
        Param.new("headers", "object", "json"),
      ] + auth_headers(project_id)

      emit(@result, base, "POST", execute_params, details, "appwrite", "function-execute:#{id}", TAG_SOURCE)
      emit(@result, base, "GET", auth_headers(project_id), details, "appwrite", "function-executions:#{id}", TAG_SOURCE)
      emit(@result, "#{base}/{executionId}", "GET", auth_headers(project_id), details, "appwrite", "function-execution:#{id}", TAG_SOURCE)
    end

    private def emit_bucket(node : JSON::Any, project_id : String, details : Details)
      bucket = node.as_h?
      return unless bucket
      id = bucket["$id"]?.try(&.as_s?)
      return unless id

      base = "/v1/storage/buckets/#{id}/files"
      upload_params = [
        Param.new("fileId", "string", "form"),
        Param.new("file", "string", "form"),
        Param.new("permissions", "array", "form"),
      ] + auth_headers(project_id)

      emit(@result, base, "GET", [Param.new("queries", "", "query"), Param.new("search", "", "query")] + auth_headers(project_id), details, "appwrite", "bucket-list:#{id}", TAG_SOURCE)
      emit(@result, base, "POST", upload_params, details, "appwrite", "bucket-upload:#{id}", TAG_SOURCE)
      emit(@result, "#{base}/{fileId}", "GET", auth_headers(project_id), details, "appwrite", "bucket-read:#{id}", TAG_SOURCE)
      emit(@result, "#{base}/{fileId}", "DELETE", auth_headers(project_id), details, "appwrite", "bucket-delete:#{id}", TAG_SOURCE)
      emit(@result, "#{base}/{fileId}/download", "GET", auth_headers(project_id), details, "appwrite", "bucket-download:#{id}", TAG_SOURCE)
    end

    # `X-Appwrite-Project` carries a concrete value we parsed out of the
    # config, which makes the emitted endpoints directly replayable.
    private def auth_headers(project_id : String) : Array(Param)
      [
        Param.new("X-Appwrite-Project", project_id, "header"),
        Param.new("X-Appwrite-Key", "", "header"),
      ]
    end
  end
end
