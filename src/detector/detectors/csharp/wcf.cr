require "../../../models/detector"
require "../../../miniparsers/wcf_extractor"

module Detector::CSharp
  class Wcf < Detector
    detector_for "cs_wcf", extensions: %w[.cs]

    def detect(filename : String, file_contents : String) : Bool
      Noir::WcfExtractor.wcf_source?(file_contents)
    end
  end
end
