require "../../../models/detector"

module Detector::Php
  class Symfony < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with Symfony dependencies
      if filename.ends_with?("composer.json") && file_contents.includes?("symfony/")
        return true
      end

      # Check for Symfony directory structure
      if filename.includes?("config/bundles.php") && file_contents.includes?("Symfony\\")
        return true
      end

      if filename.includes?("config/services.yaml") && file_contents.includes?("App\\")
        return true
      end

      # Check for Symfony namespaces in PHP files (real imports only)
      if filename.ends_with?(".php") && file_contents.match(/(^|\n)\s*use\s+Symfony\\/)
        return true
      end

      # Check for kernel.php or typical Symfony structure
      if filename.includes?("src/Kernel.php") || filename.includes?("public/index.php")
        if file_contents.includes?("Symfony")
          return true
        end
      end

      false
    end

    def set_name
      @name = "php_symfony"
    end
  end
end
