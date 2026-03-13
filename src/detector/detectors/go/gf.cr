require "../../../models/detector"

module Detector::Go
  class Gf < Detector
    def detect(filename : String, file_contents : String) : Bool
      (filename.includes? "go.mod") && (file_contents.includes? "github.com/gogf/gf")
    end

    def set_name
      @name = "go_gf"
    end
  end
end
