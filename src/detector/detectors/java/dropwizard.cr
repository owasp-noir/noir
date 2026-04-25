require "../../../models/detector"

module Detector::Java
  class Dropwizard < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.dropwizard")
    end

    def set_name
      @name = "java_dropwizard"
    end
  end
end
