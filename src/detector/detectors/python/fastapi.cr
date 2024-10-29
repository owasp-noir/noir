require "../../../models/detector"

module Detector::Python
  class FastAPI < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes? "from fastapi")
        true
      else
        false
      end
    end

    def set_name
      @name = "python_fastapi"
    end
  end
end
