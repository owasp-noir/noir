require "../../../models/detector"

module Detector::Java
  class Vaadin < Detector
    detector_for "java_vaadin", extensions: %w[.java .gradle .gradle.kts .xml]

    SOURCE_MARKERS = Regex.union("com.vaadin.flow.router", "com.vaadin.hilla", "dev.hilla")
    BUILD_MARKERS  = Regex.union("com.vaadin", "dev.hilla")

    def detect(filename : String, file_contents : String) : Bool
      return content_matches?(file_contents, SOURCE_MARKERS) if filename.ends_with?(".java")
      return false if filename.ends_with?(".xml") && File.basename(filename) != "pom.xml"

      content_matches?(file_contents, BUILD_MARKERS)
    end
  end
end
