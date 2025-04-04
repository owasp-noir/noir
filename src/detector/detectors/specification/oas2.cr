require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas2 < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if valid_json? file_contents
        data = JSON.parse(file_contents)
        begin
          if data["swagger"].as_s.includes? "2."
            check = true
            locator = CodeLocator.instance
            locator.push("swagger-json", filename)
          end
        rescue
        end
      elsif valid_yaml? file_contents
        data = YAML.parse(file_contents)
        begin
          if data["swagger"].as_s.includes? "2."
            check = true
            locator = CodeLocator.instance
            locator.push("swagger-yaml", filename)
          end
        rescue
        end
      end

      check
    end

    def set_name
      @name = "oas2"
    end
  end
end
