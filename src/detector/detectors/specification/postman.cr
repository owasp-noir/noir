require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Postman < Detector
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
            locator.push("postman-json", filename)
          end
        rescue e
          logger.debug "Postman detection failed for #{filename}: #{e}"
        end
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json")
    end

    def set_name
      @name = "postman"
    end

    # Registers Postman collection paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def postman_json_candidate?(content : String) : Bool
      content.includes?("schema.getpostman.com") ||
        content.includes?("schema.postman.com") ||
        content.includes?("\"_postman_id\"")
    end
  end
end
