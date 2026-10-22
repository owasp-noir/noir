require "../../../models/detector"

module Detector::Python
  class FastAPI < Detector
    detector_for "python_fastapi", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      (filename.ends_with? ".py") && (file_contents.includes?("from fastapi") || file_contents.includes?("import fastapi"))
    end
  end
end
