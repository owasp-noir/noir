require "../../../models/detector"

module Detector::Kotlin
  class Ktor < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".kt") && (file_contents.includes? "io.ktor")
        return true
      end

      false
    end

    def set_name
      @name = "kotlin_ktor"
    end
  end
end
