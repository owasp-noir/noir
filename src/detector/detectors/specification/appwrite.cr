require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  # Appwrite projects declare their databases, collections/tables,
  # functions and storage buckets in `appwrite.json` (the CLI writes
  # `appwrite.config.json` from v6). The server generates the whole
  # REST surface from that file, so it is the only thing to read.
  class Appwrite < Detector
    CONFIG_FILENAMES = {"appwrite.json", "appwrite.config.json"}

    # `projectId` is mandatory in every Appwrite config and is the
    # cheap gate before paying for a JSON parse.
    PROJECT_ID_MARKER = /"projectId"\s*:/

    # At least one resource family has to be present for the file to
    # describe any surface at all. `tables`/`tablesDB` are the >=1.6
    # names for `collections`.
    RESOURCE_KEYS = {"collections", "tables", "tablesDB", "databases", "functions", "buckets"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.matches?(PROJECT_ID_MARKER)

      data = json_any?(file_contents)
      return false unless data
      root = data.as_h?
      return false unless root

      return false unless root["projectId"]?.try(&.as_s?)
      return false unless RESOURCE_KEYS.any? { |key| root.has_key?(key) }

      CodeLocator.instance.push("appwrite-config", filename)
      true
    end

    # Pinned to the two CLI-generated filenames. Nothing else in a
    # project tree is named this, so the detector never reads an
    # unrelated `.json`.
    def applicable?(filename : String) : Bool
      CONFIG_FILENAMES.includes?(File.basename(filename))
    end

    def set_name
      @name = "appwrite"
    end

    # Registers each config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
