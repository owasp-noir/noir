require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"
require "har"

module Detector::Specification
  class Har < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".har") || (filename.ends_with? ".json")
        if valid_json? file_contents
          begin
            data = HAR.from_string(file_contents)
            if data.version.to_s.includes? "1."
              locator = CodeLocator.instance
              locator.push("har-path", filename)
              return true
            end
          rescue
          end
        end
      end

      false
    end

    def set_name
      @name = "har"
    end
  end
end
