require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Bruno < Detector
    BLOCK_HEADER = /^[ \t]*(meta|get|post|put|patch|delete|head|options)[ \t]*\{/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".bru")
      return false unless file_contents.matches?(BLOCK_HEADER)

      locator = CodeLocator.instance
      locator.push("bruno-bru", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".bru")
    end

    def set_name
      @name = "bruno"
    end

    # Registers Bruno `.bru` paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
