require "../../../models/detector"

module Detector::Java
  class JaxRs < Detector
    detector_for "java_jaxrs", extensions: %w[.java]

    # Frameworks that ride on JAX-RS but ship their own detector.
    # Quarkus / Dropwizard / Helidon MP projects should report as that
    # specific framework, not as plain JAX-RS.
    DERIVATIVE_MARKERS = ["io.quarkus", "io.dropwizard", "io.helidon.microprofile"]

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

    # Manifest basenames a derivative framework can *only* show up in.
    # Helidon MP's own quickstart is the concrete case: its JAX-RS
    # resource classes carry no `io.helidon` import at all — the
    # runtime is pulled in solely via `pom.xml`'s
    # `io.helidon.microprofile.*` dependencies, so a `.java`-only scan
    # would never see the marker and this detector would double-report
    # both `java_jaxrs` and `java_helidon_mp` for the same project.
    DERIVATIVE_MANIFEST_GLOBS = %w[pom.xml build.gradle build.gradle.kts]

    private def compute_derivative_project(root : String) : Bool
      java_glob = File.join(root, "src/main/java/**/*.java")
      fallback_glob = File.join(root, "**/*.java")
      candidates = Dir.glob(java_glob)
      candidates = Dir.glob(fallback_glob) if candidates.empty?
      candidates += DERIVATIVE_MANIFEST_GLOBS.map { |name| File.join(root, name) }

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
