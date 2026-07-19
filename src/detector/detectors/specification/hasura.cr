require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  # Hasura tracks tables in its metadata directory and generates GraphQL
  # root fields for each. Two layouts exist and both are current:
  #
  #   * a flat `tables.yaml` holding an array of `- table: {...}` entries
  #   * the CLI v3 layout, where `tables.yaml` is only an index of
  #     `"!include public_users.yaml"` strings and each table lives in
  #     its own file as a top-level mapping
  #
  # A detector written to the first shape alone finds nothing in a
  # modern project, so both are accepted.
  #
  # `- table:` on its own is a plausible shape in unrelated YAML (dbt
  # models, Airflow, Metabase), so a `/metadata/` path segment is
  # required and the document must also carry a key from Hasura's own
  # permission/relationship vocabulary.
  class Hasura < Detector
    METADATA_SEGMENT = "/metadata/"

    TABLE_MARKER = /^\s*(?:-\s+)?table\s*:/m
    REST_MARKER  = /^\s*(?:-\s+)?url\s*:/m

    # Keys that only a Hasura table definition carries, as one precompiled
    # alternation rather than a dozen `String#includes?` passes — each of
    # those is a full scan of the file.
    HASURA_VOCABULARY = /\b(?:select_permissions|insert_permissions|update_permissions|delete_permissions|object_relationships|array_relationships|configuration|is_enum|apollo_federation_config|remote_relationships|computed_fields|event_triggers)\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      if File.basename(filename) == "rest_endpoints.yaml"
        return detect_rest_endpoints(filename, file_contents)
      end

      detect_tables(filename, file_contents)
    end

    # Memo safety: `applicable?` consults the path
    # (metadata/** directory gate), not just the basename.
    def path_sensitive? : Bool
      true
    end

    def applicable?(filename : String) : Bool
      return false unless filename.ends_with?(".yaml") || filename.ends_with?(".yml")

      path = filename.includes?('\\') ? filename.gsub('\\', '/') : filename
      return true if path.includes?(METADATA_SEGMENT) || path.starts_with?("metadata/")

      basename = File.basename(path)
      basename == "tables.yaml" || basename == "rest_endpoints.yaml"
    end

    def set_name
      @name = "hasura"
    end

    # Registers every metadata path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def detect_rest_endpoints(filename : String, file_contents : String) : Bool
      return false unless file_contents.matches?(REST_MARKER)

      data = yaml_any?(file_contents)
      return false unless data
      entries = data.as_a?
      return false unless entries

      valid = entries.any? do |entry|
        node = entry.as_h?
        next false unless node
        !node[YAML::Any.new("url")]?.nil? && !node[YAML::Any.new("methods")]?.nil?
      end
      return false unless valid

      CodeLocator.instance.push("hasura-rest-endpoints", filename)
      true
    end

    private def detect_tables(filename : String, file_contents : String) : Bool
      return false unless file_contents.matches?(TABLE_MARKER)
      return false unless file_contents.matches?(HASURA_VOCABULARY)

      data = yaml_any?(file_contents)
      return false unless data
      return false unless table_document?(data)

      CodeLocator.instance.push("hasura-tables", filename)
      true
    end

    private def table_document?(data : YAML::Any) : Bool
      if entries = data.as_a?
        # The flat form. `!include` index files are arrays of strings and
        # carry no table definition of their own.
        return entries.any? { |entry| entry.as_h?.try(&.has_key?(YAML::Any.new("table"))) || false }
      end

      if root = data.as_h?
        # The CLI v3 per-table form.
        return root.has_key?(YAML::Any.new("table"))
      end

      false
    end
  end
end
