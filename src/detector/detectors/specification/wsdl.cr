require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class WSDL < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.includes?("wsdl:definitions") ||
                          file_contents.includes?("<definitions")
      return false unless file_contents.includes?("http://schemas.xmlsoap.org/wsdl/") ||
                          file_contents.includes?("http://www.w3.org/ns/wsdl")

      locator = CodeLocator.instance
      locator.push("wsdl-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".wsdl") || filename.ends_with?(".xml")
    end

    def set_name
      @name = "wsdl"
    end

    # Registers WSDL paths in `CodeLocator` for the analyzer pass to
    # consume. Must keep running after the first match so every spec
    # in a multi-WSDL repo is captured.
    def idempotent? : Bool
      false
    end
  end
end
