require "../../../models/detector"

module Detector::Perl
  # Detects Perl command-line apps via Getopt::Long / Getopt::Std, App::Cmd,
  # MooseX::Getopt, or explicit @ARGV indexing. Never gates on bare %ENV
  # (Mojolicious/Dancer2 config).
  class Cli < Detector
    MARKERS = /\buse\s+Getopt::(?:Long|Std)\b|\bGetOptions\s*\(|\bgetopts?\s*\(|\buse\s+App::Cmd\b|\bMooseX::Getopt\b|\$ARGV\s*\[\s*\d+\s*\]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".pl") || filename.ends_with?(".pm") || filename.ends_with?(".t")
    end

    def set_name
      @name = "perl_cli"
    end
  end
end
