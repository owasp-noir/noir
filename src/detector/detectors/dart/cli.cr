require "../../../models/detector"

module Detector::Dart
  # Detects Dart command-line apps via the args package (ArgParser /
  # CommandRunner), dcli, or `main(List<String> args)` + args indexing. Never
  # gates on bare Platform.environment (shelf/dart_frog config).
  class Cli < Detector
    detector_for "dart_cli", extensions: %w[.dart]

    MARKERS = /package:args\/|package:dcli\/|\bArgParser\s*\(|\bCommandRunner\b|\bextends\s+Command\b|main\s*\(\s*List<String>/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".dart")
      content_matches?(file_contents, MARKERS)
    end
  end
end
