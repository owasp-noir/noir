require "../../../models/detector"

module Detector::Dart
  class Http < Detector
    detector_for "dart_http", extensions: %w[.dart]

    DART_IO_IMPORT_RE = /^\s*import\s+['"]dart:io['"]/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".dart")
      return false unless file_contents.match(DART_IO_IMPORT_RE)

      file_contents.includes?("HttpServer") || file_contents.includes?("HttpRequest")
    end
  end
end
