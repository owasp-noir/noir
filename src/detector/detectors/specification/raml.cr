require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class RAML < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if valid_yaml? file_contents
        if file_contents.includes? "#%RAML"
          begin
            YAML.parse(file_contents)
            check = true
            locator = CodeLocator.instance
            locator.push("raml-spec", filename)
          rescue
          end
        end
      end

      check
    end

    def set_name
      @name = "raml"
    end
  end
end
