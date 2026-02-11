require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class RAML < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if (filename.ends_with?(".raml") || filename.ends_with?(".yaml") || filename.ends_with?(".yml"))
        if file_contents.includes?("#%RAML")
          if valid_yaml?(file_contents)
            begin
              YAML.parse(file_contents)
              check = true
              locator = CodeLocator.instance
              locator.push("raml-spec", filename)
            rescue
            end
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
