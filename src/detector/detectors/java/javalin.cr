require "../../../models/detector"

module Detector::Java
  class Javalin < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.javalin")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java")
    end

    def set_name
      @name = "java_javalin"
    end
  end
end
