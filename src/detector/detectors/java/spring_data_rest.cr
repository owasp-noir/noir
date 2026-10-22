require "../../../models/detector"

module Detector::Java
  class SpringDataRest < Detector
    detector_for "java_spring_data_rest", extensions: %w[.java .gradle .gradle.kts .xml]

    SOURCE_MARKERS = Regex.union("org.springframework.data.rest")
    BUILD_MARKERS  = Regex.union("spring-boot-starter-data-rest", "spring-data-rest-webmvc", "spring-data-rest-core", "starter.data.rest")

    def detect(filename : String, file_contents : String) : Bool
      return content_matches?(file_contents, SOURCE_MARKERS) if filename.ends_with?(".java")
      return false if filename.ends_with?(".xml") && File.basename(filename) != "pom.xml"

      content_matches?(file_contents, BUILD_MARKERS)
    end
  end
end
