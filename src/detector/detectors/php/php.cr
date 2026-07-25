require "../../../models/detector"

module Detector::Php
  class Php < Detector
    detector_for "php_pure", extensions: %w[.php .phtml], basenames: %w[composer.json composer.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".php")

      check = file_contents.includes?("<?")
      check = check || file_contents.includes?("?>")

      check
    end
  end
end
