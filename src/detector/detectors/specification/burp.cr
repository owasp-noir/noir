require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  # Burp Suite sitemap XML exports root at `<items burpVersion="...">`.
  # That attribute is documented and distinctive enough to use as the
  # single detection signal — both checks gate the path push so WSDL
  # and other XML files aren't mistakenly registered.
  class Burp < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.includes?("<items") && file_contents.includes?("burpVersion=")

      locator = CodeLocator.instance
      locator.push("burp-sitemap", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".xml")
    end

    def set_name
      @name = "burp"
    end

    # Registers Burp sitemap paths in `CodeLocator` for the analyzer pass.
    # Must keep firing past the first match so multi-file sitemaps land in
    # the locator.
    def idempotent? : Bool
      false
    end
  end
end
