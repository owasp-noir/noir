require "../../../models/detector"

module Detector::C
  # Cesanta Mongoose embedded web server: its header.
  class Mongoose < Detector
    detector_for "c_mongoose", extensions: %w[.c .h .cc .cpp .cxx .hpp]

    MARKERS = %w[mongoose.h]

    def detect(filename : String, file_contents : String) : Bool
      MARKERS.any? { |marker| file_contents.includes?(marker) }
    end
  end
end
