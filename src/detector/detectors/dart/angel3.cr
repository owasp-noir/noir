require "../../../models/detector"

module Detector::Dart
  class Angel3 < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `pubspec.yaml` listing the `angel3_framework` dependency is the
      # canonical project marker.
      if base == "pubspec.yaml" && file_contents.match(/(^|\n)\s*angel3?_framework\s*:/)
        return true
      end

      # Source-side: any Dart file importing the Angel framework package.
      return false unless filename.ends_with?(".dart")
      return true if file_contents.includes?("package:angel3_framework/")
      return true if file_contents.includes?("package:angel_framework/")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".dart") || File.basename(filename) == "pubspec.yaml" || File.basename(filename) == "pubspec.lock"
    end

    def set_name
      @name = "dart_angel3"
    end
  end
end
