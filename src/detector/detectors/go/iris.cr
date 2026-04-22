require "../../../models/detector"

module Detector::Go
  class Iris < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/kataras/iris")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_iris"
    end
  end
end
