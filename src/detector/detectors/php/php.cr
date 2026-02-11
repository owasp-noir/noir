require "../../../models/detector"

module Detector::Php
  class Php < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".php")

      check = file_contents.includes?("<?")
      check = check || file_contents.includes?("?>")

      check
    end

    def set_name
      @name = "php_pure"
    end
  end
end
