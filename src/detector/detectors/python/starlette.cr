require "../../../models/detector"

module Detector::Python
  class Starlette < Detector
    detector_for "python_starlette", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      (filename.ends_with? ".py") && (file_contents.includes?("from starlette") || file_contents.includes?("import starlette"))
    end
  end
end
