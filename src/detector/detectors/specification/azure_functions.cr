require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class AzureFunctions < Detector
    FUNCTION_JSON = "function.json"

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless valid_json?(file_contents)
      return false unless file_contents.includes?("httpTrigger")

      CodeLocator.instance.push("azure-functions-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      File.basename(filename) == FUNCTION_JSON
    end

    def set_name
      @name = "azure_functions"
    end

    # Registers each function.json path in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
