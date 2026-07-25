require "../../../models/detector"

module Detector::Go
  class Chi < Detector
    detector_for "go_chi", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/go-chi/chi")
        true
      else
        false
      end
    end
  end
end
