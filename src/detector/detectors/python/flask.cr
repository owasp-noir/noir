require "../../../models/detector"

module Detector::Python
  class Flask < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes? ".py") && (file_contents.includes? "from flask")
        true
      else
        false
      end
    end

    def set_name
      @name = "python_flask"
    end
  end
end
