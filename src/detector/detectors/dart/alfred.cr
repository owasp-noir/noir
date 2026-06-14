require "../../../models/detector"

module Detector::Dart
  class Alfred < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `pubspec.yaml` listing the `alfred` dependency is the canonical
      # project marker.
      if base == "pubspec.yaml" && file_contents.match(/(^|\n)\s*alfred\s*:/)
        return true
      end

      # Source-side: any Dart file importing `package:alfred/...`.
      return false unless filename.ends_with?(".dart")
      return true if file_contents.includes?("package:alfred/")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".dart") || File.basename(filename) == "pubspec.yaml" || File.basename(filename) == "pubspec.lock"
    end

    def set_name
      @name = "dart_alfred"
    end
  end
end
