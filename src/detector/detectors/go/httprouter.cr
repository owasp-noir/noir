require "../../../models/detector"

module Detector::Go
  class Httprouter < Detector
    detector_for "go_httprouter", extensions: %w[.go], path_segments: %w[go.mod]

    IMPORT_PATTERN = Regex.union("github.com/julienschmidt/httprouter")

    def detect(filename : String, file_contents : String) : Bool
      go_dependency?(filename, file_contents, IMPORT_PATTERN)
    end
  end
end
