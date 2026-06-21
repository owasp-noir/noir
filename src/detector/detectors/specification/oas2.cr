require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas2 < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      return false unless file_contents.includes?("swagger")

      if filename.ends_with?(".json")
        begin
          data = JSON.parse(file_contents)
          if data["swagger"].as_s.includes? "2."
            check = true
            locator = CodeLocator.instance
            locator.push("swagger-json", filename)
          end
        rescue e
          logger.debug "OAS2 JSON detection failed for #{filename}: #{e}"
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        begin
          data = parse_yaml(file_contents)
          if data["swagger"].as_s.includes? "2."
            check = true
            locator = CodeLocator.instance
            locator.push("swagger-yaml", filename)
          end
        rescue e
          logger.debug "OAS2 YAML detection failed for #{filename}: #{e}"
        end
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "oas2"
    end

    # Registers every OAS2 spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    def idempotent? : Bool
      false
    end
  end
end
