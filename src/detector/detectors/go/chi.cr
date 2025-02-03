require "../../../models/detector"

module Detector::Go
  class Chi < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/go-chi/chi")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_chi"
    end
  end
end
