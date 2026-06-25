require "../../../models/detector"

module Detector::Scala
  # Detects Scala command-line apps via scopt, decline, or mainargs. Never
  # gates on bare sys.env (Akka/Play config).
  class Cli < Detector
    MARKERS = /\bscopt\b|\bOParser\b|\bcom\.monovore\.decline\b|\bimport\s+com\.monovore\.decline|\bOpts\.(?:option|flag|argument|arguments)\b|\bmainargs\b|@main\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".scala") || filename.ends_with?(".sc")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".scala") || filename.ends_with?(".sc")
    end

    def set_name
      @name = "scala_cli"
    end
  end
end
