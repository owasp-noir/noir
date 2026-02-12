require "../../../models/detector"

module Detector::Java
  class Jsp < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?(".jsp")

      check = file_contents.includes?("<%")
      check = check && file_contents.includes?("%>")

      check
    end

    def set_name
      @name = "java_jsp"
    end
  end
end
