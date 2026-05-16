require "../../../models/detector"

module Detector::Java
  class JaxRs < Detector
    # Frameworks that ride on JAX-RS but ship their own detector.
    # Quarkus / Dropwizard projects should report as that specific
    # framework, not as plain JAX-RS.
    DERIVATIVE_MARKERS = ["io.quarkus", "io.dropwizard"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      return false if DERIVATIVE_MARKERS.any? { |marker| file_contents.includes?(marker) }
      file_contents.includes?("jakarta.ws.rs") || file_contents.includes?("javax.ws.rs")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".xml") || filename.ends_with?(".properties") || filename.ends_with?(".yml") || filename.ends_with?(".yaml")
    end

    def set_name
      @name = "java_jaxrs"
    end
  end
end
