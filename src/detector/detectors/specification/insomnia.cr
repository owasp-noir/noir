require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Insomnia < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if filename.ends_with?(".json")
        return false unless file_contents.includes?("\"__export_format\"") && file_contents.includes?("\"_type\"")

        begin
          data = JSON.parse(file_contents)
          # Insomnia v4 export: top-level `_type: "export"` + `__export_format`
          type_field = data["_type"]?.try(&.as_s?)
          if type_field == "export" && data["__export_format"]?
            check = true
            locator = CodeLocator.instance
            locator.push("insomnia-json", filename)
          end
        rescue e
          logger.debug "Insomnia JSON detection failed for #{filename}: #{e}"
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        return false unless file_contents.includes?(".insomnia.rest/")

        begin
          data = YAML.parse(file_contents)
          # Insomnia v5: top-level `type: "<...>.insomnia.rest/5.x"`.
          # Insomnia ships several namespaces (spec.insomnia.rest/5.0,
          # collection.insomnia.rest/5.0, environment.insomnia.rest/5.0).
          # We only care about collection exports.
          type_field = data["type"]?.try(&.as_s?)
          if type_field && type_field.includes?(".insomnia.rest/") &&
             (type_field.starts_with?("collection.") || type_field.starts_with?("spec."))
            check = true
            locator = CodeLocator.instance
            locator.push("insomnia-yaml", filename)
          end
        rescue e
          logger.debug "Insomnia YAML detection failed for #{filename}: #{e}"
        end
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "insomnia"
    end

    # Registers Insomnia export paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
