require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/cloudwego/hertz")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_hertz"
    end
  end
end
