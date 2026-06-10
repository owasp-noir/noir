require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Mobile
  class Android < Detector
    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "AndroidManifest.xml" && file_contents.includes?("<manifest")
        locator = CodeLocator.instance
        locator.push("android-manifest", filename)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      File.basename(filename) == "AndroidManifest.xml"
    end

    def set_name
      @name = "android"
    end

    # Registers AndroidManifest.xml paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
