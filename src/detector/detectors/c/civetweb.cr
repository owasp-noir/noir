require "../../../models/detector"

module Detector::C
  # CivetWeb (C API and the C++ CivetServer wrapper): its header.
  class Civetweb < Detector
    detector_for "c_civetweb", extensions: %w[.c .h .cc .cpp .cxx .hpp]

    MARKERS = %w[civetweb.h CivetServer.h]

    def detect(filename : String, file_contents : String) : Bool
      MARKERS.any? { |marker| file_contents.includes?(marker) }
    end
  end
end
