require "../../../models/detector"

module Detector::Java
  class Vaadin < Detector
    detector_for "java_vaadin", extensions: %w[.java .gradle .gradle.kts .xml]

    # Hilla's `@Endpoint` packages; Spring Boot Actuator has an `@Endpoint` too.
    HILLA_MARKERS  = Regex.union("com.vaadin.hilla", "dev.hilla", "com.vaadin.flow.server.connect", "com.vaadin.fusion")
    SOURCE_MARKERS = Regex.union(HILLA_MARKERS, Regex.union("com.vaadin.flow.router"))
    # `com.vaadin` as a group / plugin id, not `com.vaadin.external.google`
    # (the android-json exclusion every Spring Boot starter carries).
    BUILD_MARKERS = /com\.vaadin(?![.\w])|dev\.hilla/

    def detect(filename : String, file_contents : String) : Bool
      return content_matches?(file_contents, SOURCE_MARKERS) if filename.ends_with?(".java")
      return false if filename.ends_with?(".xml") && File.basename(filename) != "pom.xml"

      content_matches?(file_contents, BUILD_MARKERS)
    end
  end
end
