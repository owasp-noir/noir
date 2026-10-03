require "../../../models/detector"

module Detector::Python
  class Robyn < Detector
    detector_for "python_robyn", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      (filename.ends_with? ".py") && (file_contents.includes?("from robyn") || file_contents.includes?("import robyn"))
    end
  end
end
