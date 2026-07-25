require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Mobile
  class Ios < Detector
    # Registers Info.plist / .entitlements paths in `CodeLocator`.
    detector_for "ios", extensions: %w[.plist .entitlements], idempotent: false

    def detect(filename : String, file_contents : String) : Bool
      locator = CodeLocator.instance

      if filename.ends_with?(".plist") && file_contents.includes?("CFBundleURLTypes")
        locator.push("ios-info-plist", filename)
        return true
      end

      if filename.ends_with?(".entitlements") && file_contents.includes?("com.apple.developer.associated-domains")
        locator.push("ios-entitlements", filename)
        return true
      end

      false
    end
  end
end
