require "../../../models/detector"

module Detector::Go
  class Revel < Detector
    detector_for "go_revel", extensions: %w[.go], path_segments: %w[go.mod]

    # `require github.com/revel/revel` in go.mod or the import in a source
    # file. The analyzer additionally needs a `conf/routes` beside the app.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("go.mod") || filename.ends_with?(".go")

      file_contents.includes?("github.com/revel/revel")
    end
  end
end
