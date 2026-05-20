require "../../../models/detector"

module Detector::Php
  class Hyperf < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?("composer.json") && (file_contents.includes?("hyperf/hyperf") ||
         file_contents.includes?("hyperf/framework") ||
         file_contents.includes?("hyperf/http-server"))
        return true
      end

      if filename.ends_with?(".php") && file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+Hyperf\\[^;\n]*;/)
        return true
      end

      if filename.ends_with?(".php") && (file_contents.includes?("Hyperf\\HttpServer\\Router") ||
         file_contents.includes?("Hyperf\\HttpServer\\Annotation"))
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || filename.ends_with?(".phtml") || File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
    end

    def set_name
      @name = "php_hyperf"
    end
  end
end
