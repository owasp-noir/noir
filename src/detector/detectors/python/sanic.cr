require "../../../models/detector"

module Detector::Python
  class Sanic < Detector
    detector_for "python_sanic", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes? "from sanic")
        true
      else
        false
      end
    end
  end
end
