require "../../../models/detector"

module Detector::Dart
  class GetServer < Detector
    detector_for "dart_get_server", extensions: %w[.dart], basenames: %w[pubspec.yaml pubspec.lock]

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `pubspec.yaml` listing the `get_server` dependency is the canonical
      # project marker.
      if base == "pubspec.yaml" && file_contents.match(/(^|\n)\s*get_server\s*:/)
        return true
      end

      # Source-side: any Dart file importing `package:get_server/...`.
      return false unless filename.ends_with?(".dart")
      return true if file_contents.includes?("package:get_server/")

      false
    end
  end
end
