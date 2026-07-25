require "../../../models/detector"

module Detector::Go
  class Gin < Detector
    detector_for "go_gin", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/gin-gonic/gin")
        true
      else
        false
      end
    end
  end
end
