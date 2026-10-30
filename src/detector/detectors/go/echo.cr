require "../../../models/detector"

module Detector::Go
  class Echo < Detector
    detector_for "go_echo", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/labstack/echo")
    end
  end
end
