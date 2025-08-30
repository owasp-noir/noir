require "../../../models/detector"

module Detector::Php
  class Symfony < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with Symfony dependencies
      if filename.ends_with?("composer.json") && file_contents.includes?("symfony/")
        return true
      end

      # Check for Symfony directory structure
      if filename.includes?("config/bundles.php") || filename.includes?("config/services.yaml")
        return true
      end

      # Check for Symfony namespaces in PHP files
      if filename.ends_with?(".php") && file_contents.includes?("use Symfony\\")
        return true
      end

      # Check for Symfony annotations/attributes
      if filename.ends_with?(".php") && (file_contents.includes?("@Route") || file_contents.includes?("#[Route"))
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