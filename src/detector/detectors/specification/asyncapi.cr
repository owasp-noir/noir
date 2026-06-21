require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class AsyncApi < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      return false unless file_contents.includes?("asyncapi")

      if filename.ends_with?(".json")
        begin
          data = JSON.parse(file_contents)
          version = data["asyncapi"].as_s
          if version.starts_with?("2.") || version.starts_with?("3.")
            check = true
            locator = CodeLocator.instance
            locator.push("asyncapi-json", filename)
          end
        rescue e
          logger.debug "AsyncAPI JSON detection failed for #{filename}: #{e}"
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        begin
          data = YAML.parse(file_contents)
          version = data["asyncapi"].as_s
          if version.starts_with?("2.") || version.starts_with?("3.")
            check = true
            locator = CodeLocator.instance
            locator.push("asyncapi-yaml", filename)
          end
        rescue e
          logger.debug "AsyncAPI YAML detection failed for #{filename}: #{e}"
        end
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "asyncapi"
    end

    # Registers every AsyncAPI spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    def idempotent? : Bool
      false
    end
  end
end
