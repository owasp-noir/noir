require "../../../models/detector"

module Detector::Scala
  class Akka < Detector
    detector_for "scala_akka", extensions: %w[.scala .sbt], basenames: %w[build.sbt]

    # Apache Pekko HTTP (`org.apache.pekko.http`) is the ASF fork of Akka
    # HTTP with the same route DSL, so it rides this detector and analyzer.
    # Anchored on `import` so `pekko.http.*` config keys in strings and
    # comments don't fire.
    HTTP_IMPORT_RE = /\bimport\s+(?:akka|org\.apache\.pekko)\.http\b/

    def detect(filename : String, file_contents : String) : Bool
      filename.ends_with?(".scala") && file_contents.matches?(HTTP_IMPORT_RE)
    end
  end
end
