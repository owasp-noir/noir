require "../../../models/detector"

module Detector::Kotlin
  class Ktor < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".kt") && (file_contents.includes? "io.ktor")
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".kt") || filename.ends_with?(".kts") || filename.ends_with?(".java") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".xml") || filename.ends_with?(".properties")
    end

    def set_name
      @name = "kotlin_ktor"
    end
  end
end
