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

    def set_name
      @name = "java_armeria"
    end
  end
end
