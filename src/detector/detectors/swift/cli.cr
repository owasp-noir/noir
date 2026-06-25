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
      file_contents.includes?("import ArgumentParser") || file_contents.matches?(PARSABLE) ||
        file_contents.matches?(WRAPPERS) || file_contents.matches?(SWIFTCLI) ||
        file_contents.matches?(COMMANDER) || file_contents.matches?(CMDLINE)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".swift")
    end

    def set_name
      @name = "swift_cli"
    end
  end
end
