require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Postman < Detector
    # Registers Postman collection paths in `CodeLocator`.
    detector_for "postman", extensions: %w[.json], idempotent: false

    # Every `.json` in the tree reaches this guard.
    CANDIDATE_MARKER = Regex.union(
      "schema.getpostman.com", "schema.postman.com", "\"_postman_id\"",
    )

    def detect(filename : String, file_contents : String) : Bool
      check = false
      if filename.ends_with?(".json") && postman_json_candidate?(file_contents)
        begin
          data = JSON.parse(file_contents)
          # Check for Postman Collection v2.1.0 or v2.0.0 schema
          if data["info"]? && data["info"]["schema"]?
            schema = data["info"]["schema"].as_s
            if schema.includes?("schema.getpostman.com") || schema.includes?("schema.postman.com")
              check = true
            end
          elsif data["info"]? && data["info"]["_postman_id"]? && data["item"]?.try(&.as_a?)
            check = true
          end

          if check
            locator = CodeLocator.instance
            locator.push(Noir::LocatorKeys::POSTMAN_JSON, filename)
          end
        rescue e
          logger.debug "Postman detection failed for #{filename}: #{e}"
          record_unparsable_document(filename, e)
        end
      end

      check
    end

    private def postman_json_candidate?(content : String) : Bool
      content_matches?(content, CANDIDATE_MARKER)
    end
  end
end
