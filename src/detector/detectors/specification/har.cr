require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"
require "har"

module Detector::Specification
  class Har < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".har") || (filename.ends_with? ".json")
        if filename.ends_with?(".har") || har_json_candidate?(file_contents)
          begin
            data = HAR.from_string(file_contents)
            if data.version.to_s.includes? "1."
              locator = CodeLocator.instance
              locator.push("har-path", filename)
              return true
            end
          rescue e
            logger.debug "HAR detection failed for #{filename}: #{e}"
          end
        end
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".har") || filename.ends_with?(".json")
    end

    def set_name
      @name = "har"
    end

    # Registers HAR file paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def har_json_candidate?(content : String) : Bool
      content.includes?("\"log\"") && content.includes?("\"entries\"")
    end
  end
end
