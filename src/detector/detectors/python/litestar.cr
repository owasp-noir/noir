require "../../../models/detector"

module Detector::Python
  class Litestar < Detector
    detector_for "python_litestar", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes?("from litestar") || file_contents.includes?("import litestar"))
        true
      else
        false
      end
    end
  end
end
