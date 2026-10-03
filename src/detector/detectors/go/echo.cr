require "../../../models/detector"

module Detector::Go
  class Echo < Detector
    detector_for "go_echo", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      (filename.includes? "go.mod") && (file_contents.includes? "github.com/labstack/echo")
    end
  end
end
