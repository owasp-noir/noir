require "../../../models/detector"

module Detector::Php
  class Laravel < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with Laravel dependencies
      if filename.ends_with?("composer.json") && file_contents.includes?("laravel/framework")
        return true
      end

      # Check for Laravel directory structure and key files
      if filename.includes?("routes/web.php") || filename.includes?("routes/api.php")
        return true
      end

      if filename.includes?("bootstrap/app.php") && file_contents.includes?("Laravel")
        return true
      end

      if filename == "artisan" && file_contents.includes?("Illuminate\\Foundation\\Application")
        return true
      end

      # Check for Laravel namespaces in PHP files
      if filename.ends_with?(".php") && file_contents.includes?("use Illuminate\\")
        return true
      end

      # Check for Laravel controller structure
      if filename.includes?("app/Http/Controllers/") && filename.ends_with?(".php")
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

    def set_name
      @name = "php_laravel"
    end
  end
end
