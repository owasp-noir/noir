require "../../../models/detector"

module Detector::Java
  class Dropwizard < Detector
    detector_for "java_dropwizard", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.dropwizard")
    end
  end
end
