require "../../../models/detector"

module Detector::Scala
  class Akka < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (file_contents.includes? "akka.http")
        return true
      end

      false
    end

    def set_name
      @name = "scala_akka"
    end
  end
end
