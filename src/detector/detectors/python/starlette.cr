require "../../../models/detector"

module Detector::Python
  class Starlette < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes?("from starlette") || file_contents.includes?("import starlette"))
        true
      else
        false
      end
    end

    def set_name
      @name = "python_starlette"
    end
  end
end
