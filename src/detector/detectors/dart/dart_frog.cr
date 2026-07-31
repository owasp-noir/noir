require "../../../models/detector"

module Detector::Dart
  class DartFrog < Detector
    detector_for "dart_frog", extensions: %w[.dart], basenames: %w[pubspec.yaml pubspec.lock]

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `pubspec.yaml` listing the `dart_frog` dependency is the
      # canonical project marker.
      if base == "pubspec.yaml" && file_contents.match(/(^|\n)\s*dart_frog\s*:/)
        return true
      end

      # Source-side: any Dart file importing `package:dart_frog/...`
      # or living under a `routes/` directory and exporting an
      # `onRequest` handler.
      return false unless filename.ends_with?(".dart")

      if file_contents.includes?("package:dart_frog/")
        return true
      end

      # Scan-base-relative: `routes/` is Dart Frog's project-root
      # convention, not a directory the checkout happens to sit under.
      if base_relative_path(filename).includes?("/routes/") &&
         file_contents.match(/\b(?:Response|Future<Response>)\s+onRequest\s*\(/)
        return true
      end

      false
    end
  end
end
