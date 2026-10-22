require "../../../models/detector"

module Detector::Java
  class HelidonMp < Detector
    detector_for "java_helidon_mp",
      extensions: %w[.java pom.xml build.gradle build.gradle.kts]

    # Helidon MP resource classes are frequently plain JAX-RS with no
    # direct Helidon import — the MP runtime is pulled in only via the
    # build manifest (or a bootstrap `Main` calling
    # `io.helidon.microprofile.server.Server`). So this checks both:
    # a `.java` file that references the MP runtime directly, or a
    # build manifest declaring a `io.helidon.microprofile` dependency.
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".java")
        return file_contents.includes?("io.helidon.microprofile")
      end

      if filename.includes?("pom.xml") || filename.includes?("build.gradle") || filename.includes?("build.gradle.kts")
        return file_contents.includes?("io.helidon.microprofile")
      end

      false
    end
  end
end
