require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Smithy < Detector
    # Registers every `.smithy` path in `CodeLocator` for the analyzer
    # pass; must keep running after the first match.
    detector_for "smithy", extensions: %w[.smithy], idempotent: false

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".smithy")
      return false unless file_contents.includes?("$version")

      locator = CodeLocator.instance
      locator.push(Noir::LocatorKeys::SMITHY_SPEC, filename)
      true
    end
  end
end
