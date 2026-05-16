require "../../../models/detector"

module Detector::Dart
  class Serverpod < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `pubspec.yaml` listing any `serverpod*` package is the canonical
      # project marker. Common variants include `serverpod`,
      # `serverpod_server`, `serverpod_client`, and `serverpod_auth_*`.
      if base == "pubspec.yaml" && file_contents.match(/(^|\n)\s*serverpod(?:_[a-z0-9_]+)?\s*:/)
        return true
      end

      return false unless filename.ends_with?(".dart")

      return true if file_contents.includes?("package:serverpod/serverpod.dart")
      return true if file_contents.match(/\bextends\s+(StreamingEndpoint|Endpoint)\b/)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".dart") || File.basename(filename) == "pubspec.yaml" || File.basename(filename) == "pubspec.lock"
    end

    def set_name
      @name = "dart_serverpod"
    end
  end
end
