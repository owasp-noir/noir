require "../../../models/detector"

module Detector::Java
  class Armeria < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (
           (filename.includes? "pom.xml") || (filename.includes? "build.gradle") ||
           (filename.includes? "build.gradle.kts") || (filename.includes? "settings.gradle.kts")
         ) && (file_contents.includes? "com.linecorp.armeria")
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".xml") || filename.ends_with?(".properties") || filename.ends_with?(".yml") || filename.ends_with?(".yaml")
    end

    def set_name
      @name = "java_armeria"
    end
  end
end
