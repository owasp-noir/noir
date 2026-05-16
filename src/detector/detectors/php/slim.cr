require "../../../models/detector"

module Detector::Php
  class Slim < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?("composer.json") && file_contents.includes?("slim/slim")
        return true
      end

      if filename.ends_with?(".php") && (file_contents.includes?("use Slim\\") ||
         file_contents.includes?("namespace Slim\\") ||
         file_contents.includes?("Slim\\Factory\\AppFactory") ||
         file_contents.includes?("SlimFramework"))
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || filename.ends_with?(".phtml") || File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
    end

    def set_name
      @name = "php_slim"
    end
  end
end
