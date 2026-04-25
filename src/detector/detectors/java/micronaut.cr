require "../../../models/detector"

module Detector::Java
  class Micronaut < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.micronaut") || file_contents.includes?("micronaut.io")
    end

    def set_name
      @name = "java_micronaut"
    end
  end
end
