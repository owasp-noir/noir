require "../../../models/detector"

module Detector::Php
  class Symfony < Detector
    detector_for "php_symfony",
      extensions: %w[.php .phtml],
      basenames: %w[composer.json composer.lock]

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
      if filename.ends_with?(".php") && file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+Symfony\\[^;\n]*;/)
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
  end
end
