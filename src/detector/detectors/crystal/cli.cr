require "../../../models/detector"

module Detector::Crystal
  # Detects Crystal command-line apps via stdlib OptionParser, explicit ARGV
  # indexing, or a CLI shard (clim, admiral, commander). Never gates on bare
  # ENV (ubiquitous in Crystal web apps).
  class Cli < Detector
    MARKERS = /\bOptionParser\.(?:parse|new)\b|\bARGV\s*\[\s*\d+\s*\]|<\s*Clim\b|<\s*Admiral::Command\b|\bCommander::Command\b|\brequire\s+"(?:clim|admiral|commander)"/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cr")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cr")
    end

    def set_name
      @name = "crystal_cli"
    end
  end
end
