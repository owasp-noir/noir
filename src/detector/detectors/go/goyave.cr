require "../../../models/detector"

module Detector::Go
  class Goyave < Detector
    detector_for "go_goyave", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "goyave.dev/goyave")
        true
      else
        false
      end
    end
  end
end
