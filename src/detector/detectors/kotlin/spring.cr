require "../../../models/detector"

module Detector::Kotlin
  class Spring < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".kt") && (file_contents.includes? "org.springframework")
        return true
      end

      false
    end

    def set_name
      @name = "kotlin_spring"
    end
  end
end
