require "../../../models/detector"

module Detector::Go
  class Beego < Detector
    detector_for "go_beego", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/beego/beego")
    end
  end
end
