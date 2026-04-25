require "../../../models/detector"

module Detector::Java
  class JaxRs < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("jakarta.ws.rs") || file_contents.includes?("javax.ws.rs")
    end

    def set_name
      @name = "java_jaxrs"
    end
  end
end
