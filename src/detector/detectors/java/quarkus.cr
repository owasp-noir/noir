require "../../../models/detector"

module Detector::Java
  class Quarkus < Detector
    detector_for "java_quarkus", extensions: %w[.java .kt]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java") || filename.ends_with?(".kt")
      file_contents.includes?("io.quarkus") || file_contents.includes?("quarkus.io")
    end
  end
end
