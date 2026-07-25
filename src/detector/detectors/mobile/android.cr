require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Mobile
  class Android < Detector
    # Registers AndroidManifest.xml paths in `CodeLocator`.
    detector_for "android", basenames: %w[AndroidManifest.xml], idempotent: false

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "AndroidManifest.xml" && file_contents.includes?("<manifest")
        locator = CodeLocator.instance
        locator.push("android-manifest", filename)
        return true
      end

      false
    end
  end
end
