require "../../../models/detector"

module Detector::Groovy
  class Grails < Detector
    # Memo safety: `applicable?` consults the path
    # (/grails-app/ gate), not just the basename.
    #
    # The gate matches that segment on the RAW path while `detect` matches
    # it on `base_relative_path`, so the gate is deliberately the wider of
    # the two. It only decides whether `detect` is dispatched — `detect`
    # is what answers — and keeping it a pure string test keeps the
    # per-file lookup off the base resolution.
    detector_for "groovy_grails",
      extensions: %w[.groovy .gsp .gradle .gradle.kts .java .yml .yaml .xml],
      path_segments: %w[/grails-app/]

    GRADLE_FILES = {"build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"}

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # Gradle build / settings scripts in either DSL.
      if GRADLE_FILES.includes?(base) &&
         (file_contents.match(/['"]org\.grails(?:\.[a-z0-9_]+)?:[\w.-]+/) ||
         file_contents.match(/group:\s*['"]org\.grails(?:\.[a-z0-9_]+)?['"]/) ||
         file_contents.match(/apply\s+plugin:\s*['"]org\.grails\./) ||
         file_contents.match(/id\s+['"]org\.grails\./))
        return true
      end

      # Maven `pom.xml` referencing `org.grails*` groupIds or `grails-*`
      # artifacts.
      if base == "pom.xml" &&
         (file_contents.match(/<groupId>\s*org\.grails(?:\.[a-z0-9_]+)?\s*<\/groupId>/) ||
         file_contents.match(/<artifactId>\s*grails-[\w-]+\s*<\/artifactId>/))
        return true
      end

      # Any file under the conventional `grails-app/` layout — controllers,
      # services, domain classes, taglibs, views, conf, etc.
      #
      # Base-relative, not the raw path: this branch has no content check,
      # so on the absolute path a checkout that merely *sat* under some
      # unrelated `grails-app/` directory made every file in the project —
      # `.py` included — report as Grails.
      return true if base_relative_path(filename).includes?("/grails-app/")

      # GSP (Groovy Server Pages) files only exist in Grails projects.
      return true if filename.ends_with?(".gsp")

      # `application.yml` / `application.groovy` carrying a `grails:` block.
      if (base == "application.yml" || base == "application.groovy") &&
         file_contents.match(/^\s*grails\s*:/m)
        return true
      end

      return false unless filename.ends_with?(".groovy")

      return true if file_contents.includes?("import grails.")

      false
    end
  end
end
