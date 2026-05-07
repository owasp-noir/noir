require "../../../models/detector"

module Detector::Groovy
  class Grails < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # Gradle build script referencing the Grails plugin / dependencies.
      if (base == "build.gradle" || base == "build.gradle.kts") &&
         (file_contents.match(/['"]org\.grails:grails-/) ||
         file_contents.match(/['"]org\.grails\.grails-(?:web|core|plugins|gsp)['"]/) ||
         file_contents.match(/apply\s+plugin:\s*['"]org\.grails\./) ||
         file_contents.match(/id\s+['"]org\.grails\./))
        return true
      end

      # Conventional grails-app/ directory layout.
      return true if filename.includes?("/grails-app/controllers/")
      return true if filename.includes?("/grails-app/conf/UrlMappings")

      # `application.yml` / `application.groovy` carrying a `grails:` block.
      if (base == "application.yml" || base == "application.groovy") &&
         file_contents.match(/^\s*grails\s*:/m)
        return true
      end

      return false unless filename.ends_with?(".groovy")

      return true if file_contents.includes?("import grails.")

      false
    end

    def set_name
      @name = "groovy_grails"
    end
  end
end
