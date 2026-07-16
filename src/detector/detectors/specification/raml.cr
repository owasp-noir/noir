require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class RAML < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if filename.ends_with?(".raml") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        if file_contents.includes?("#%RAML")
          # `valid_yaml?` already proves the content parses; the previous
          # second `YAML.parse` (result discarded) doubled the cost for
          # nothing.
          if valid_yaml?(file_contents)
            check = true
            locator = CodeLocator.instance
            locator.push("raml-spec", filename)
          end
        end
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".raml") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "raml"
    end

    # Registers RAML spec paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
