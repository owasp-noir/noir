require "../../../models/detector"

module Detector::Go
  class Revel < Detector
    detector_for "go_revel", extensions: %w[.go], path_segments: %w[go.mod]

    IMPORT_PATTERN = Regex.union("github.com/revel/revel")

    # `require github.com/revel/revel` in go.mod or the import in a source
    # file. The analyzer additionally needs a `conf/routes` beside the app.
    def detect(filename : String, file_contents : String) : Bool
      go_dependency?(filename, file_contents, IMPORT_PATTERN)
    end
  end
end
