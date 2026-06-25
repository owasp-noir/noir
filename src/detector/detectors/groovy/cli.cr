require "../../../models/detector"

module Detector::Groovy
  # Detects Groovy command-line apps via the built-in CliBuilder or picocli
  # annotations. Never gates on bare System.getenv (Grails config).
  class Cli < Detector
    MARKERS = /\bnew\s+CliBuilder\b|\bCliBuilder\s*\(|@picocli|@Command\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".groovy")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".groovy")
    end

    def set_name
      @name = "groovy_cli"
    end
  end
end
