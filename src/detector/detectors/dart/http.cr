require "../../../models/detector"

module Detector::Dart
  class Http < Detector
    DART_IO_IMPORT_RE = /^\s*import\s+['"]dart:io['"]/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".dart")
      return false unless file_contents.match(DART_IO_IMPORT_RE)

      file_contents.includes?("HttpServer") || file_contents.includes?("HttpRequest")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".dart")
    end

    def set_name
      @name = "dart_http"
    end
  end
end
