require "../../../models/detector"

module Detector::Scala
  class Http4s < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".scala") || filename.ends_with?(".sbt") || File.basename(filename) == "build.sbt"

      if file_contents.includes?("org.http4s") || file_contents.includes?("http4s-dsl")
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".scala") || filename.ends_with?(".sbt") || File.basename(filename) == "build.sbt"
    end

    def set_name
      @name = "scala_http4s"
    end
  end
end
