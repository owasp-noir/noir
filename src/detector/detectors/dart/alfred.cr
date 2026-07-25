require "../../../models/detector"

module Detector::Dart
  class Alfred < Detector
    detector_for "dart_alfred", extensions: %w[.dart], basenames: %w[pubspec.yaml pubspec.lock]

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
  end
end
