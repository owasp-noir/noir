require "../../../models/detector"

module Detector::Elixir
  # Detects Elixir command-line apps via OptionParser, System.argv, or the
  # optimus library. Never gates on bare System.get_env (Phoenix config).
  class Cli < Detector
    detector_for "elixir_cli", extensions: %w[.ex .exs]

    MARKERS = /\bOptionParser\.(?:parse|parse!|next)\b|\bSystem\.argv\b|\bOptimus\.new!?\b|\buse\s+Optimus\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ex") || filename.ends_with?(".exs")
      content_matches?(file_contents, MARKERS)
    end
  end
end
