require "../../../models/detector"

module Detector::C
  # GNU libmicrohttpd: its header or `MHD_start_daemon`.
  class Libmicrohttpd < Detector
    detector_for "c_libmicrohttpd", extensions: %w[.c .h .cc .cpp .cxx .hpp]

    MARKERS = %w[microhttpd.h MHD_start_daemon]

    def detect(filename : String, file_contents : String) : Bool
      MARKERS.any? { |marker| file_contents.includes?(marker) }
    end
  end
end
