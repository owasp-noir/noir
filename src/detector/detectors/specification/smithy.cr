require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Smithy < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".smithy")
      return false unless file_contents.includes?("$version")

      locator = CodeLocator.instance
      locator.push("smithy-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".smithy")
    end

    def set_name
      @name = "smithy"
    end

    # Registers every `.smithy` path in `CodeLocator` for the analyzer
    # pass; must keep running after the first match.
    def idempotent? : Bool
      false
    end
  end
end
