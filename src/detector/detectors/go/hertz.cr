require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/cloudwego/hertz")
    end
  end
end
