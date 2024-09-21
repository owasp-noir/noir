require "../../../models/detector"

module Detector::Java
  class Jsp < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("<%")
      check = check && file_contents.includes?("%>")
      check = check && filename.includes?(".jsp")

      check
    end

    def set_name
      @name = "java_jsp"
    end
  end
end
