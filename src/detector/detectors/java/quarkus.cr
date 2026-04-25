require "../../../models/detector"

module Detector::Java
  class Quarkus < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.quarkus") || file_contents.includes?("quarkus.io")
    end

    def set_name
      @name = "java_quarkus"
    end
  end
end
