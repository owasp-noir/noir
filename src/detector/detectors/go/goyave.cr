require "../../../models/detector"

module Detector::Go
  class Goyave < Detector
    detector_for "go_goyave", extensions: %w[.go], path_segments: %w[go.mod]

    IMPORT_PATTERN = Regex.union("goyave.dev/goyave")

    def detect(filename : String, file_contents : String) : Bool
      go_dependency?(filename, file_contents, IMPORT_PATTERN)
    end
  end
end
