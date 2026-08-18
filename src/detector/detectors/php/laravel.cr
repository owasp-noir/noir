require "../../../models/detector"

module Detector::Php
  class Laravel < Detector
    detector_for "php_laravel",
      extensions: %w[.php .phtml],
      basenames: %w[artisan composer.json composer.lock]

    # Bootstrap markers every real `artisan` carries: the `LARAVEL_START`
    # timestamp (Laravel 5 through 12) or the console-kernel resolution
    # that precedes it in the pre-11 skeleton. `artisan` is a common
    # enough word to need one.
    ARTISAN_BOOTSTRAP = /\bLARAVEL_START\b|Illuminate\\(?:Foundation\\Application|Contracts\\Console\\Kernel)/

    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with Laravel dependencies
      if filename.ends_with?("composer.json") && file_contents.includes?("laravel/framework")
        return true
      end

      # Route files. `routes/web.php` and `routes/api.php` are conventions
      # Slim, hand-rolled routers and plain PHP share, so the filename
      # alone proves nothing — require a Laravel routing symbol too.
      # Matched base-relative so a `routes/` directory *above* the scan
      # base cannot claim the file either.
      if (base_relative_path(filename).includes?("/routes/web.php") ||
         base_relative_path(filename).includes?("/routes/api.php")) &&
         (file_contents.includes?("Route::") || file_contents.includes?("Illuminate\\"))
        return true
      end

      if filename.includes?("bootstrap/app.php") && file_contents.includes?("Laravel")
        return true
      end

      # Laravel's extension-less console entrypoint. Compared on the
      # basename: `filename` is a path (`./artisan`, `app/artisan`), so
      # the old `filename == "artisan"` could never be true.
      if File.basename(filename) == "artisan" &&
         content_matches?(file_contents, ARTISAN_BOOTSTRAP)
        return true
      end

      # Check for Laravel namespaces in PHP files
      if filename.ends_with?(".php") && (file_contents.includes?("use Illuminate\\") ||
         file_contents.includes?("namespace Illuminate\\") ||
         file_contents.includes?("use Laravel\\") ||
         file_contents.includes?("namespace Laravel\\"))
        return true
      end

      # Check for Laravel controller structure. Base-relative for the same
      # reason as the route files above.
      if base_relative_path(filename).includes?("/app/Http/Controllers/") && filename.ends_with?(".php")
        if file_contents.includes?("use Illuminate\\") || file_contents.includes?("Controller")
          return true
        end
      end

      # Check for Laravel-specific directories and files
      if filename.includes?("config/app.php") && file_contents.includes?("Laravel")
        return true
      end

      false
    end
  end
end
