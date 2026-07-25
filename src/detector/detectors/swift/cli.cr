require "../../../models/detector"

module Detector::Swift
  # Detects Swift command-line applications. SOURCE-anchored (never
  # Package.swift, where swift-argument-parser is a transitive dep): a
  # ParsableCommand conformance, ArgumentParser property wrappers, SwiftCLI /
  # Commander, or builtin CommandLine.arguments.
  class Cli < Detector
    PARSABLE  = /\b(?:struct|enum|class)\s+\w+\s*:\s*[^\{]*\b(?:Async)?ParsableCommand\b/
    WRAPPERS  = /@(?:Option|Argument|Flag|OptionGroup)\b/
    SWIFTCLI  = /\bimport\s+SwiftCLI\b/
    COMMANDER = /\bimport\s+Commander\b/
    CMDLINE   = /\bCommandLine\.arguments\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".swift")
      file_contents.includes?("import ArgumentParser") || content_matches?(file_contents, PARSABLE) ||
        content_matches?(file_contents, WRAPPERS) || content_matches?(file_contents, SWIFTCLI) ||
        content_matches?(file_contents, COMMANDER) || content_matches?(file_contents, CMDLINE)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".swift")
    end

    def set_name
      @name = "swift_cli"
    end
  end
end
