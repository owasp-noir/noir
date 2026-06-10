require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Mobile
  # Detects the server-side half of a mobile universal-link association —
  # the well-known files a host publishes so the OS will open an app for
  # its URLs:
  #
  #   * Android App Links  — /.well-known/assetlinks.json (Digital Asset Links)
  #   * iOS Universal Links — apple-app-site-association (often extensionless,
  #                           sometimes /.well-known/apple-app-site-association.json)
  #
  # Matched by basename plus a content marker so an unrelated assetlinks.json /
  # JSON blob doesn't register. Both file types feed the single
  # `well_known_applinks` analyzer via the CodeLocator.
  class WellKnown < Detector
    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)
      locator = CodeLocator.instance

      if basename == "assetlinks.json" && file_contents.includes?("delegate_permission")
        locator.push("android-assetlinks", filename)
        return true
      end

      if aasa_basename?(basename) && file_contents.includes?("applinks")
        locator.push("ios-aasa", filename)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      basename = File.basename(filename)
      basename == "assetlinks.json" || aasa_basename?(basename)
    end

    def set_name
      @name = "well_known_applinks"
    end

    # Registers assetlinks.json / apple-app-site-association paths in
    # `CodeLocator`, so it must run on every candidate file.
    def idempotent? : Bool
      false
    end

    private def aasa_basename?(basename : String) : Bool
      basename == "apple-app-site-association" ||
        basename == "apple-app-site-association.json"
    end
  end
end
