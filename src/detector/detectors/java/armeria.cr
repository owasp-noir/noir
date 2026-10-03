require "../../../models/detector"

module Detector::Java
  class Armeria < Detector
    detector_for "java_armeria",
      extensions: %w[pom.xml build.gradle build.gradle.kts settings.gradle.kts]

    def detect(filename : String, file_contents : String) : Bool
      (
        (filename.includes? "pom.xml") || (filename.includes? "build.gradle") ||
          (filename.includes? "build.gradle.kts") || (filename.includes? "settings.gradle.kts")
      ) && (file_contents.includes? "com.linecorp.armeria")
    end
  end
end
