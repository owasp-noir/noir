require "../../../models/detector"

module Detector::Python
  class Tornado < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes?("import tornado") || file_contents.includes?("from tornado"))
        true
      else
        false
      end
    end

    def set_name
      @name = "python_tornado"
    end
  end
end
