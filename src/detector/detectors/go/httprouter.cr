require "../../../models/detector"

module Detector::Go
  class Httprouter < Detector
    detector_for "go_httprouter", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/julienschmidt/httprouter")
        true
      else
        false
      end
    end
  end
end
