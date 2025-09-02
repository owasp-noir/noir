require "../../../models/detector"

module Detector::Go
  class Fasthttp < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? "go.mod") && 
         (file_contents.includes? "github.com/valyala/fasthttp") &&
         !file_contents.includes?("github.com/gofiber/fiber")
        true
      else
        false
      end
    end

    def set_name
      @name = "go_fasthttp"
    end
  end
end