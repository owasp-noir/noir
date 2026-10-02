require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class AzureFunctions < Detector
    # Registers each function.json path in `CodeLocator`.
    detector_for "azure_functions", idempotent: false, basenames: %w[function.json]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      # Substring guard before the full JSON parse — both must pass, so the
      # cheaper check goes first.
      return false unless file_contents.includes?("httpTrigger")
      return false unless valid_json?(file_contents)

      CodeLocator.instance.push(Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC, filename)
      true
    end
  end
end
