require "../../../models/detector"

module Detector::Php
  class Lumen < Detector
    detector_for "php_lumen",
      extensions: %w[.php .phtml],
      basenames: %w[composer.json composer.lock]

    def detect(filename : String, file_contents : String) : Bool
      # composer.json explicitly pulling in lumen-framework is the strongest signal.
      if filename.ends_with?("composer.json") && file_contents.includes?("laravel/lumen-framework")
        return true
      end

      # Lumen bootstraps `Laravel\Lumen\Application` (distinct from Laravel's
      # `Illuminate\Foundation\Application`).
      if filename.includes?("bootstrap/app.php") && file_contents.includes?("Laravel\\Lumen\\Application")
        return true
      end

      # Any PHP file pulling in the Lumen namespace.
      if filename.ends_with?(".php") && (file_contents.includes?("use Laravel\\Lumen\\") ||
         file_contents.includes?("namespace Laravel\\Lumen\\"))
        return true
      end

      false
    end
  end
end
