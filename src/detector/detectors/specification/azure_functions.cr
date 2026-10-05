require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"
require "../../../miniparsers/azure_functions_extractor"

module Detector::Specification
  class AzureFunctions < Detector
    # Registers each function.json path, and each source file declaring a
    # code-first HTTP trigger (C# isolated/in-process, Python v2, Node v4),
    # in `CodeLocator`.
    detector_for "azure_functions", idempotent: false, basenames: %w[function.json],
      extensions: %w[.cs .py .js .mjs .cjs .ts .mts .cts]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      if File.basename(filename) == "function.json"
        # Substring guard before the full JSON parse — both must pass, so the
        # cheaper check goes first.
        return false unless file_contents.includes?("httpTrigger")
        return false unless json_any?(file_contents)
      else
        return false unless Noir::AzureFunctionsExtractor.code_first?(filename, file_contents)
      end

      CodeLocator.instance.push(Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC, filename)
      true
    end
  end
end
