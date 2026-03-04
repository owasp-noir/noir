require "../../../models/detector"

module Detector::Java
  class Vertx < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (
           (filename.ends_with?("pom.xml")) || (filename.ends_with?("build.gradle")) ||
           (filename.ends_with?("build.gradle.kts")) || (filename.ends_with?("settings.gradle.kts")) || (filename.ends_with?(".java"))
         ) && (file_contents.includes? "io.vertx")
        true
      else
        false
      end
    end

    def set_name
      @name = "java_vertx"
    end
  end
end
