require "../../../models/detector"

module Detector::Go
  class Httprouter < Detector
    detector_for "go_httprouter", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/julienschmidt/httprouter")
    end
  end
end
