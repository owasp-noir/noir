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
      return false if derivative_project?(filename)
      file_contents.includes?("jakarta.ws.rs") || file_contents.includes?("javax.ws.rs")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".xml") || filename.ends_with?(".properties") || filename.ends_with?(".yml") || filename.ends_with?(".yaml")
    end

    def set_name
      @name = "java_jaxrs"
    end

    private def derivative_project?(filename : String) : Bool
      root = project_root_for(filename)
      java_glob = File.join(root, "src/main/java/**/*.java")
      fallback_glob = File.join(root, "**/*.java")
      candidates = Dir.glob(java_glob)
      candidates = Dir.glob(fallback_glob) if candidates.empty?

      candidates.any? do |path|
        next false unless File.file?(path)

        begin
          content = File.read(path)
          DERIVATIVE_MARKERS.any? { |marker| content.includes?(marker) }
        rescue
          false
        end
      end
    end

    private def project_root_for(path : String) : String
      marker = "/src/main/java/"
      if index = path.index(marker)
        path[...index]
      else
        File.dirname(path)
      end
    end
  end
end
