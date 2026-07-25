require "../../../models/detector"

module Detector::Java
  class Micronaut < Detector
    detector_for "java_micronaut", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.micronaut") || file_contents.includes?("micronaut.io")
    end
  end
end
