require "../../../models/detector"

module Detector::Java
  class Vertx < Detector
    detector_for "java_vertx",
      extensions: %w[.java pom.xml build.gradle build.gradle.kts settings.gradle.kts]

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
  end
end
