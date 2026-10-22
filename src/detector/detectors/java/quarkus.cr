require "../../../models/detector"

module Detector::Java
  class Quarkus < Detector
    detector_for "java_quarkus", extensions: %w[.java .kt], basenames: %w[pom.xml build.gradle build.gradle.kts]

    # The official starter's resource classes import only `jakarta.ws.rs`;
    # Quarkus itself is named only by the build manifest, so read both.
    def detect(filename : String, file_contents : String) : Bool
      return file_contents.includes?("io.quarkus") if filename.ends_with?("pom.xml") || filename.ends_with?("build.gradle") || filename.ends_with?("build.gradle.kts")
      return false unless filename.ends_with?(".java") || filename.ends_with?(".kt")
      file_contents.includes?("io.quarkus") || file_contents.includes?("quarkus.io")
    end
  end
end
