require "../../../models/detector"

module Detector::Python
  class Litestar < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes?("from litestar") || file_contents.includes?("import litestar"))
        true
      else
        false
      end
    end

    def set_name
      @name = "python_litestar"
    end
  end
end
