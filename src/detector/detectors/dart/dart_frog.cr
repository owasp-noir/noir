require "../../../models/detector"

module Detector::Dart
  class DartFrog < Detector
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

      if filename.includes?("/routes/") &&
         file_contents.match(/\b(?:Response|Future<Response>)\s+onRequest\s*\(/)
        return true
      end

      false
    end

    def set_name
      @name = "dart_frog"
    end
  end
end
