require "../../../models/detector"

module Detector::Dart
  class Shelf < Detector
    detector_for "dart_shelf", extensions: %w[.dart], basenames: %w[pubspec.yaml pubspec.lock]

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `pubspec.yaml` listing `shelf_router` or `shelf` is the canonical
      # project marker. We accept both because many backends import
      # `shelf` directly and only pull in `shelf_router` indirectly via
      # a higher-level helper, but the analyzer keys off `Router()`
      # which both setups expose.
      if base == "pubspec.yaml" && file_contents.match(/(^|\n)\s*(?:shelf_router|shelf)\s*:/)
        return true
      end

      return false unless filename.ends_with?(".dart")

      return true if file_contents.includes?("package:shelf_router/")
      return true if file_contents.includes?("package:shelf/shelf.dart") && file_contents.includes?("Router(")

      false
    end
  end
end
