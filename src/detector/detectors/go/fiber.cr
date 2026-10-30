require "../../../models/detector"

module Detector::Go
  class Fiber < Detector
    detector_for "go_fiber", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/gofiber/fiber")
    end
  end
end
