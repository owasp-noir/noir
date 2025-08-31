require "../../../models/detector"

module Detector::Python
  class Sanic < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes? "from sanic")
        true
      else
        false
      end
    end

    def set_name
      @name = "python_sanic"
    end
  end
end
