require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Mobile
  class Ios < Detector
    # Registers Info.plist / .entitlements paths in `CodeLocator`.
    detector_for "ios", extensions: %w[.plist .entitlements], idempotent: false

    def detect(filename : String, file_contents : String) : Bool
      locator = CodeLocator.instance

      if filename.ends_with?(".plist") && file_contents.includes?("CFBundleURLTypes")
        locator.push(Noir::LocatorKeys::IOS_INFO_PLIST, filename)
        return true
      end

      if filename.ends_with?(".entitlements") && file_contents.includes?("com.apple.developer.associated-domains")
        locator.push(Noir::LocatorKeys::IOS_ENTITLEMENTS, filename)
        return true
      end

      false
    end
  end
end
