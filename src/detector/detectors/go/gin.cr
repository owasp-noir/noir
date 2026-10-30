require "../../../models/detector"

module Detector::Go
  class Gin < Detector
    detector_for "go_gin", extensions: %w[.go], path_segments: %w[go.mod]

    IMPORT_PATTERN = Regex.union("github.com/gin-gonic/gin")

    def detect(filename : String, file_contents : String) : Bool
      go_dependency?(filename, file_contents, IMPORT_PATTERN)
    end
  end
end
