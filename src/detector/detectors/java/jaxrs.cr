require "../../../models/detector"
require "../../../utils/path_scope"

module Detector::Java
  class JaxRs < Detector
    detector_for "java_jaxrs", extensions: %w[.java .kt]

    # Frameworks that ride on JAX-RS but ship their own detector.
    # Quarkus / Dropwizard / Helidon MP projects should report as that
    # specific framework, not as plain JAX-RS.
    # `io.dropwizard.metrics` is the standalone Metrics library (its own
    # Maven groupId), which plain Jersey apps depend on without Dropwizard.
    DERIVATIVE_MARKERS_RE = /io\.quarkus|io\.dropwizard(?!\.metrics)|io\.helidon\.microprofile/

    # `derivative_project?` answers a project-wide question — "does any
    # source file under this root pull in Quarkus/Dropwizard?" — whose
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

    def requires_scan_files? : Bool
      true
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java") || filename.ends_with?(".kt")
      return false unless file_contents.includes?("jakarta.ws.rs") || file_contents.includes?("javax.ws.rs")
      return false if content_matches?(file_contents, DERIVATIVE_MARKERS_RE)

      !derivative_project?(filename)
    end

    private def derivative_project?(filename : String) : Bool
      root = project_root_for(filename)
      @derivative_cache_mutex.synchronize do
        @derivative_cache.put_if_absent(root) { compute_derivative_project(root) }
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
      locator = CodeLocator.instance
      candidates = if locator.scan_files_active?
                     files = locator.source_files_under(File.join(root, "src", "main", "java"), ".java") +
                             locator.source_files_under(File.join(root, "src", "main", "kotlin"), ".kt")
                     if files.empty?
                       files = locator.source_files_under(root, ".java") + locator.source_files_under(root, ".kt")
                     end
                     files
                   else
                     files = %w[src/main/java/**/*.java src/main/kotlin/**/*.kt].flat_map { |glob| glob_under(root, glob) }
                     files.empty? ? %w[**/*.java **/*.kt].flat_map { |glob| glob_under(root, glob) } : files
                   end
      candidates.concat(DERIVATIVE_MANIFEST_GLOBS.map { |name| File.join(root, name) })

      candidates.any? do |path|
        next false unless File.file?(path)

        begin
          content = locator.read_source(path)
          content ? content_matches?(content, DERIVATIVE_MARKERS_RE) : false
        rescue
          false
        end
      end
    end

    private def project_root_for(path : String) : String
      base = @base_paths.size <= 1 ? @base_path : (Noir::PathScope.longest_base(path, @base_paths) || @base_path)
      Noir::PathScope.marker_root(path, base, {"/src/main/java/", "/src/main/kotlin/"}) || File.dirname(path)
    end
  end
end
