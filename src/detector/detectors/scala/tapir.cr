require "../../../models/detector"

module Detector::Scala
  class Tapir < Detector
    detector_for "scala_tapir", extensions: %w[.scala .sbt], basenames: %w[build.sbt]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (file_contents.includes?("sttp.tapir") || file_contents.includes?("import tapir."))
        return true
      end

      false
    end
  end
end
