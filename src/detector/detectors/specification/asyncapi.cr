require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class AsyncApi < Detector
    # Registers every AsyncAPI spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    detector_for "asyncapi", extensions: %w[.json .yaml .yml], idempotent: false

    # Every `.json`/`.yaml`/`.yml` in the tree reaches this gate.
    ASYNCAPI_MARKER = /asyncapi/

    def detect(filename : String, file_contents : String) : Bool
      check = false
      return false unless content_matches?(file_contents, ASYNCAPI_MARKER)

      if filename.ends_with?(".json")
        begin
          data = JSON.parse(file_contents)
          version = data["asyncapi"].as_s
          if version.starts_with?("2.") || version.starts_with?("3.")
            check = true
            locator = CodeLocator.instance
            locator.push(Noir::LocatorKeys::ASYNCAPI_JSON, filename)
          end
        rescue e
          logger.debug "AsyncAPI JSON detection failed for #{filename}: #{e}"
          record_unparsable_document(filename, e)
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        begin
          data = YAML.parse(file_contents)
          version = data["asyncapi"].as_s
          if version.starts_with?("2.") || version.starts_with?("3.")
            check = true
            locator = CodeLocator.instance
            locator.push(Noir::LocatorKeys::ASYNCAPI_YAML, filename)
          end
        rescue e
          logger.debug "AsyncAPI YAML detection failed for #{filename}: #{e}"
          record_unparsable_document(filename, e)
        end
      end

      check
    end
  end
end
