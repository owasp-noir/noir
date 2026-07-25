require "../../../models/detector"

module Detector::Scala
  class Akka < Detector
    detector_for "scala_akka", extensions: %w[.scala .sbt], basenames: %w[build.sbt]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (file_contents.includes? "akka.http")
        return true
      end

      false
    end
  end
end
