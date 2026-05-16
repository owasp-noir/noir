require "../../../models/detector"

module Detector::Php
  class Php < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".php")

      check = file_contents.includes?("<?")
      check = check || file_contents.includes?("?>")

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || filename.ends_with?(".phtml") || File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
    end

    def set_name
      @name = "php_pure"
    end
  end
end
