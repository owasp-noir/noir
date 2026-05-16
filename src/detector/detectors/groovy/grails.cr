require "../../../models/detector"

module Detector::Groovy
  class Grails < Detector
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
      return true if filename.includes?("/grails-app/")

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

    def applicable?(filename : String) : Bool
      filename.ends_with?(".groovy") || filename.ends_with?(".gsp") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".java") || filename.ends_with?(".yml") || filename.ends_with?(".yaml") || filename.ends_with?(".xml") || filename.includes?("/grails-app/")
    end

    def set_name
      @name = "groovy_grails"
    end
  end
end
