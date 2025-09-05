require "../../../models/detector"

module Detector::Java
  class Vertx < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (
           (filename.includes? "pom.xml") || (filename.includes? "build.gradle") ||
           (filename.includes? "build.gradle.kts") || (filename.includes? "settings.gradle.kts")
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
