require "../../../models/detector"

module Detector::Php
  # Laravel Folio: the composer package, or a `Folio::path(...)` mount /
  # `Laravel\Folio\…` import (pages pull `use function Laravel\Folio\…`).
  class Folio < Detector
    detector_for "php_folio", extensions: %w[.php], basenames: %w[composer.json]

    MARKER_RE = /\bLaravel\\Folio\\|\bFolio::path\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "composer.json"
        return file_contents.includes?(%("laravel/folio"))
      end
      Noir::FileExtension.fold(filename).ends_with?(".php") && file_contents.includes?("Folio") &&
        file_contents.matches?(MARKER_RE)
    end
  end
end
