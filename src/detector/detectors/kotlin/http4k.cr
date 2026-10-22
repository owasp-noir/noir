require "../../../models/detector"

module Detector::Kotlin
  class Http4k < Detector
    detector_for "kotlin_http4k", extensions: %w[.kt]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".kt")
      file_contents.includes?("org.http4k")
    end
  end
end
