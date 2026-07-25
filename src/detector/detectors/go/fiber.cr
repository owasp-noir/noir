require "../../../models/detector"

module Detector::Go
  class Fiber < Detector
    detector_for "go_fiber", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/gofiber/fiber")
        true
      else
        false
      end
    end
  end
end
