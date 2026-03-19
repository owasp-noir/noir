require "../../../models/detector"

module Detector::Go
  class Httprouter < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/julienschmidt/httprouter")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_httprouter"
    end
  end
end
