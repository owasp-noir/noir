require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Mobile
  class Ios < Detector
    def detect(filename : String, file_contents : String) : Bool
      locator = CodeLocator.instance

      if info_plist?(filename) && file_contents.includes?("CFBundleURLTypes")
        locator.push("ios-info-plist", filename)
        return true
      end

      if filename.ends_with?(".entitlements") && file_contents.includes?("com.apple.developer.associated-domains")
        locator.push("ios-entitlements", filename)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      info_plist?(filename) || filename.ends_with?(".entitlements")
    end

    # Xcode's default target plist is `Info.plist`, but the older (and still
    # very common in real apps) build convention names it `<Target>-Info.plist`
    # — e.g. `Wikipedia-Info.plist`, `podcasts-Info.plist`, plus per-flavor
    # variants like `Local-Info.plist`/`Staging-Info.plist`. Matching only the
    # exact `Info.plist` basename silently dropped every custom URL scheme in
    # those apps. The `CFBundleURLTypes` content gate in `detect` keeps
    # unrelated `*-Info.plist` files (e.g. `GoogleService-Info.plist`) out.
    private def info_plist?(filename : String) : Bool
      File.basename(filename).ends_with?("Info.plist")
    end

    def set_name
      @name = "ios"
    end

    # Registers Info.plist / .entitlements paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
