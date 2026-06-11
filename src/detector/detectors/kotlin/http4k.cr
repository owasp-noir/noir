require "../../../models/detector"

module Detector::Kotlin
  class Http4k < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".kt")
      file_contents.includes?("org.http4k")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".kt")
    end

    def set_name
      @name = "kotlin_http4k"
    end
  end
end
