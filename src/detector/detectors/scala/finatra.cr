require "../../../models/detector"

module Detector::Scala
  class Finatra < Detector
    detector_for "scala_finatra", extensions: %w[.scala], basenames: %w[build.sbt]

    IMPORT_RE = /\bimport\s+com\.twitter\.finatra\.http\b/

    def detect(filename : String, file_contents : String) : Bool
      return file_contents.includes?("finatra-http") if filename.ends_with?("build.sbt")
      filename.ends_with?(".scala") && file_contents.matches?(IMPORT_RE)
    end
  end
end
