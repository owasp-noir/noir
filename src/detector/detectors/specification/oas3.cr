require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas3 < Detector
    # Registers every OAS3 spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    detector_for "oas3", extensions: %w[.json .yaml .yml], idempotent: false

    # Every `.json`/`.yaml`/`.yml` in the tree reaches this gate.
    OPENAPI_MARKER = /openapi/

    def detect(filename : String, file_contents : String) : Bool
      check = false
      return false unless content_matches?(file_contents, OPENAPI_MARKER)

      if filename.ends_with?(".json")
        begin
          data = JSON.parse(file_contents)
          if data["openapi"].as_s.includes? "3."
            check = true
            locator = CodeLocator.instance
            locator.push("oas3-json", filename)
          end
        rescue e
          logger.debug "OAS3 JSON detection failed for #{filename}: #{e}"
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        begin
          data = parse_yaml(file_contents)
          if data["openapi"].as_s.includes? "3."
            check = true
            locator = CodeLocator.instance
            locator.push("oas3-yaml", filename)
          end
        rescue e
          logger.debug "OAS3 YAML detection failed for #{filename}: #{e}"
        end
      end

      check
    end
  end
end
