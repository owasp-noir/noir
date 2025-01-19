require "../../../models/detector"

module Detector::Php
  class Php < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("<?")
      check = check || file_contents.includes?("?>")
      check = check && filename.ends_with?(".php")

      check
    end

    def set_name
      @name = "php_pure"
    end
  end
end
