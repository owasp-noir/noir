require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas2 < Detector
    # Registers every OAS2 spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    detector_for "oas2", extensions: %w[.json .yaml .yml], idempotent: false

    # See `Detector::Specification::Oas3` for why the YAML gate is anchored at
    # column 0 and stands in for the parse. A bare `/swagger/` matched every
    # OpenAPI 3 document that links to its own `swagger.yaml` origin — 67 of
    # the 493 openapi-directory documents in the perf corpus — and each one
    # paid for a full YAML parse only to be rejected.
    SWAGGER2_YAML_MARKER = /^["']?swagger["']?[ \t]*:[ \t]*["']?2\./m
    SWAGGER2_JSON_MARKER = /"swagger"[ \t]*:[ \t]*"2\./

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".json")
        return false unless content_matches?(file_contents, SWAGGER2_JSON_MARKER)
        begin
          data = JSON.parse(file_contents)
          if data["swagger"].as_s.includes? "2."
            CodeLocator.instance.push(Noir::LocatorKeys::SWAGGER_JSON, filename)
            return true
          end
        rescue e
          logger.debug "OAS2 JSON detection failed for #{filename}: #{e}"
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        if content_matches?(file_contents, SWAGGER2_YAML_MARKER)
          CodeLocator.instance.push(Noir::LocatorKeys::SWAGGER_YAML, filename)
          return true
        end
      end

      false
    end
  end
end
