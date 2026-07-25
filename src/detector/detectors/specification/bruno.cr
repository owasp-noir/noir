require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Bruno < Detector
    # Registers Bruno `.bru` paths in `CodeLocator`.
    detector_for "bruno", extensions: %w[.bru], idempotent: false

    BLOCK_HEADER = /^[ \t]*(meta|get|post|put|patch|delete|head|options)[ \t]*\{/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".bru")
      return false unless content_matches?(file_contents, BLOCK_HEADER)

      locator = CodeLocator.instance
      locator.push("bruno-bru", filename)
      true
    end
  end
end
