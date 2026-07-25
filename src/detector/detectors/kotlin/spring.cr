require "../../../models/detector"

module Detector::Kotlin
  class Spring < Detector
    detector_for "kotlin_spring", extensions: %w[.kt]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".kt") && (file_contents.includes? "org.springframework")
        return true
      end

      false
    end
  end
end
