require "../../../models/detector"

module Detector::Go
  class Mux < Detector
    detector_for "go_mux", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/gorilla/mux")
        true
      else
        false
      end
    end
  end
end
