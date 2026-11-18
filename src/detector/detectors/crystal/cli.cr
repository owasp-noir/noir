require "../../../models/detector"

module Detector::Crystal
  # Detects Crystal command-line apps via stdlib OptionParser, an ARGV read
  # (`ARGV[0]`, `ARGV.first?`, `ARGV.shift?`, `ARGV == [...]`), or a CLI shard
  # (clim, admiral, commander). Never gates on bare ENV (ubiquitous in Crystal
  # web apps) or on ARGV merely passed along (`args = ARGV`).
  class Cli < Detector
    detector_for "crystal_cli", extensions: %w[.cr]

    MARKERS = /\bOptionParser\.(?:parse|new)\b|\bARGV(?:\s*\[\s*\d+\s*\]|\.(?:first|shift)\b|\s*[!=]=\s*\[)|<\s*Clim\b|<\s*Admiral::Command\b|\bCommander::Command\b|\brequire\s+"(?:clim|admiral|commander)"/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cr")
      content_matches?(file_contents, MARKERS)
    end
  end
end
