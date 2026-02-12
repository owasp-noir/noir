require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Postman < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if filename.ends_with?(".json") && valid_json?(file_contents)
        data = JSON.parse(file_contents)
        begin
          # Check for Postman Collection v2.1.0 or v2.0.0 schema
          if data["info"]? && data["info"]["schema"]?
            schema = data["info"]["schema"].as_s
            if schema.includes?("schema.getpostman.com") || schema.includes?("schema.postman.com")
              check = true
              locator = CodeLocator.instance
              locator.push("postman-json", filename)
            end
          end
        rescue
        end
      end

      check
    end

    def set_name
      @name = "postman"
    end
  end
end
