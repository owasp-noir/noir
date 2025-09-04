require "../../../models/detector"

module Detector::Go
  class Mux < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/gorilla/mux")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_mux"
    end
  end
end
