require "../../../models/detector"

module Detector::Java
  class JaxRs < Detector
    # Frameworks that ride on JAX-RS but ship their own detector.
    # Quarkus / Dropwizard projects should report as that specific
    # framework, not as plain JAX-RS.
    DERIVATIVE_MARKERS = ["io.quarkus", "io.dropwizard"]

    # `derivative_project?` answers a project-wide question — "does any
    # Java file under this root pull in Quarkus/Dropwizard?" — whose
    # answer is identical for every file that shares a root. The detector
    # instance is shared across the whole scan, so memoise per root.
    # Without this the glob+read sweep ran once per `.java` file, making
    # JAX-RS detection O(java_files²): on a Spring project jaxrs never
    # matches, so it never short-circuits and re-globbed + re-read the
    # entire source tree for every single file (~9.8s on a 686-file
    # project). Keyed by root so sibling projects in a monorepo still
    # resolve independently.
    @derivative_cache = {} of String => Bool
    @derivative_cache_mutex = Mutex.new

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      return false if DERIVATIVE_MARKERS.any? { |marker| file_contents.includes?(marker) }
      return false if derivative_project?(filename)
      file_contents.includes?("jakarta.ws.rs") || file_contents.includes?("javax.ws.rs")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java")
    end

    def set_name
      @name = "java_jaxrs"
    end

    private def derivative_project?(filename : String) : Bool
      root = project_root_for(filename)
      @derivative_cache_mutex.synchronize do
        cached = @derivative_cache[root]?
        return cached unless cached.nil?
        result = compute_derivative_project(root)
        @derivative_cache[root] = result
        result
      end
    end

    private def compute_derivative_project(root : String) : Bool
      java_glob = File.join(root, "src/main/java/**/*.java")
      fallback_glob = File.join(root, "**/*.java")
      candidates = Dir.glob(java_glob)
      candidates = Dir.glob(fallback_glob) if candidates.empty?

      locator = CodeLocator.instance
      candidates.any? do |path|
        next false unless File.file?(path)

        begin
          # The detector pass already read most of these files; reuse the
          # cached content so the one-time sweep avoids a second disk read.
          content = locator.content_for(path) || File.read(path)
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
