require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  # OData CSDL metadata documents are wrapped in `<edmx:Edmx>` and
  # carry one of the published Edmx namespace URIs. The two-signal
  # gate — root marker plus namespace — keeps generic WSDL/XML files
  # from being claimed by this detector.
  class OData < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.includes?("edmx:Edmx") || file_contents.includes?("<Edmx")
      return false unless file_contents.includes?("docs.oasis-open.org/odata") ||
                          file_contents.includes?("schemas.microsoft.com/ado/")

      locator = CodeLocator.instance
      locator.push("odata-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      return true if base == "$metadata" || base == "$metadata.xml" || base == "metadata.xml"
      filename.ends_with?(".xml") || filename.ends_with?(".edmx") || filename.ends_with?(".csdl")
    end

    def set_name
      @name = "odata"
    end

    # Registers OData spec paths for the analyzer pass. Must keep
    # firing past the first match so multi-service repos land every
    # `$metadata` document in the locator.
    def idempotent? : Bool
      false
    end
  end
end
