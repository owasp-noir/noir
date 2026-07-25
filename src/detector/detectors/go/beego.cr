require "../../../models/detector"

module Detector::Go
  class Beego < Detector
    detector_for "go_beego", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/beego/beego")
        true
      else
        false
      end
    end
  end
end
