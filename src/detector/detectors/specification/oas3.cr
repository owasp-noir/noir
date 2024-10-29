require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas3 < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if valid_json? file_contents
        data = JSON.parse(file_contents)
        begin
          if data["openapi"].as_s.includes? "3."
            check = true
            locator = CodeLocator.instance
            locator.push("oas3-json", filename)
          end
        rescue
        end
      elsif valid_yaml? file_contents
        data = YAML.parse(file_contents)
        begin
          if data["openapi"].as_s.includes? "3."
            check = true
            locator = CodeLocator.instance
            locator.push("oas3-yaml", filename)
          end
        rescue
        end
      end

      check
    end

    def set_name
      @name = "oas3"
    end
  end
end
