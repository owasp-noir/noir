require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"
require "har"

module Detector::Specification
  class Har < Detector
    # Registers HAR file paths in `CodeLocator`.
    detector_for "har", extensions: %w[.har .json], idempotent: false

    # Every `.json` in the tree reaches these guards. Both must match, so
    # they stay separate probes rather than a union.
    LOG_MARKER     = /"log"/
    ENTRIES_MARKER = /"entries"/

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

    private def har_json_candidate?(content : String) : Bool
      content_matches?(content, LOG_MARKER) && content_matches?(content, ENTRIES_MARKER)
    end
  end
end
