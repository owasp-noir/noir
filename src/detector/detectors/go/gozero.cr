require "../../../models/detector"

module Detector::Go
  class GoZero < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && (file_contents.includes? "github.com/zeromicro/go-zero")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_gozero"
    end
  end
end
