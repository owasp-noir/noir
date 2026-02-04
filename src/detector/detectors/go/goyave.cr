require "../../../models/detector"

module Detector::Go
  class Goyave < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "goyave.dev/goyave")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_goyave"
    end
  end
end
