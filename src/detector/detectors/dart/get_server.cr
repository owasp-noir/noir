require "../../../models/detector"

module Detector::Dart
  class GetServer < Detector
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

    def applicable?(filename : String) : Bool
      filename.ends_with?(".dart") || File.basename(filename) == "pubspec.yaml" || File.basename(filename) == "pubspec.lock"
    end

    def set_name
      @name = "dart_get_server"
    end
  end
end
