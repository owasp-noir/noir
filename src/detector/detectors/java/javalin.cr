require "../../../models/detector"

module Detector::Java
  class Javalin < Detector
    detector_for "java_javalin", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.javalin")
    end
  end
end
