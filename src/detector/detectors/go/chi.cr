require "../../../models/detector"

module Detector::Go
  class Chi < Detector
    detector_for "go_chi", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/go-chi/chi")
    end
  end
end
