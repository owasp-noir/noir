require "../../../models/detector"

module Detector::Scala
  class Scalatra < Detector
    detector_for "scala_scalatra", extensions: %w[.scala .sbt], basenames: %w[build.sbt]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (file_contents.includes?("org.scalatra") || file_contents.includes?("ScalatraServlet"))
        return true
      end

      false
    end
  end
end
