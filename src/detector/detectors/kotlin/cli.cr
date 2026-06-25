require "../../../models/detector"

module Detector::Kotlin
  # Detects Kotlin command-line applications. Gated on clikt / kotlinx-cli
  # imports or their constructs — NOT on bare `fun main(args)`, which Spring
  # Boot and most Kotlin apps have.
  class Cli < Detector
    LIB_IMPORTS = ["com.github.ajalt.clikt", "kotlinx.cli"]
    USAGE       = /:\s*CliktCommand\b|\bArgParser\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".kt")
      LIB_IMPORTS.any? { |marker| file_contents.includes?(marker) } || file_contents.matches?(USAGE)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".kt")
    end

    def set_name
      @name = "kotlin_cli"
    end
  end
end
