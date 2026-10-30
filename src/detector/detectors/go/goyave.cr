require "../../../models/detector"

module Detector::Go
  class Goyave < Detector
    detector_for "go_goyave", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "goyave.dev/goyave")
    end
  end
end
