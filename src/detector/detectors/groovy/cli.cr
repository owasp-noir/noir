require "../../../models/detector"

module Detector::Groovy
  # Detects Groovy command-line apps via the built-in CliBuilder, picocli
  # annotations, JCommander or Commons CLI. Gated on library-specific
  # constructs/imports only (never a bare generic token) so unrelated code
  # doesn't light this up. Never gates on bare System.getenv (Grails config).
  class Cli < Detector
    detector_for "groovy_cli", extensions: %w[.groovy]

    MARKERS = /\bnew\s+CliBuilder\b|\bCliBuilder\s*\(|@picocli|@Command\b|\bimport\s+com\.beust\.jcommander\b|\bnew\s+JCommander\s*\(|\bJCommander\.newBuilder\s*\(|\bimport\s+org\.apache\.commons\.cli\b|\bOption\.builder\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".groovy")
      content_matches?(file_contents, MARKERS)
    end
  end
end
