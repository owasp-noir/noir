require "../../../models/detector"

module Detector::Scala
  class Akka < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (file_contents.includes? "akka.http")
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".scala") || filename.ends_with?(".sbt") || File.basename(filename) == "build.sbt"
    end

    def set_name
      @name = "scala_akka"
    end
  end
end
