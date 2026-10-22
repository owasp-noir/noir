require "../../../models/detector"

module Detector::Kotlin
  # Detects Kotlin command-line applications. Gated on clikt / kotlinx-cli /
  # picocli imports or their constructs — NOT on bare `fun main(args)`, which
  # Spring Boot and most Kotlin apps have.
  class Cli < Detector
    detector_for "kotlin_cli", extensions: %w[.kt]

    LIB_IMPORTS = ["com.github.ajalt.clikt", "kotlinx.cli", "picocli.CommandLine"]
    USAGE       = /:\s*CliktCommand\b|\bArgParser\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".kt")
      LIB_IMPORTS.any? { |marker| file_contents.includes?(marker) } || content_matches?(file_contents, USAGE)
    end
  end
end
