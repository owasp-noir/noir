require "../../../models/detector"

module Detector::Python
  class Tornado < Detector
    detector_for "python_tornado", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes?("import tornado") || file_contents.includes?("from tornado"))
        true
      else
        false
      end
    end
  end
end
