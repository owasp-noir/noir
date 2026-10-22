require "../../../models/detector"

module Detector::Scala
  class ZioHttp < Detector
    detector_for "scala_zio_http", extensions: %w[.scala .sbt], basenames: %w[build.sbt]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (
           file_contents.includes?("zio.http") ||
           file_contents.includes?("zhttp.http")
         )
        return true
      end

      false
    end
  end
end
