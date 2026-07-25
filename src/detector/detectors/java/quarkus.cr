require "../../../models/detector"

module Detector::Java
  class Quarkus < Detector
    detector_for "java_quarkus", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.quarkus") || file_contents.includes?("quarkus.io")
    end
  end
end
