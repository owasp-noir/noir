require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas2 < Detector
    # Registers every OAS2 spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    detector_for "oas2", extensions: %w[.json .yaml .yml], idempotent: false

    # Every `.json`/`.yaml`/`.yml` in the tree reaches this gate.
    SWAGGER_MARKER = /swagger/

    def detect(filename : String, file_contents : String) : Bool
      check = false
      return false unless content_matches?(file_contents, SWAGGER_MARKER)

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
  end
end
