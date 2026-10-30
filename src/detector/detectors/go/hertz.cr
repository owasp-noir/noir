require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]

    IMPORT_PATTERN = Regex.union("github.com/cloudwego/hertz")

    def detect(filename : String, file_contents : String) : Bool
      go_dependency?(filename, file_contents, IMPORT_PATTERN)
    end
  end
end
