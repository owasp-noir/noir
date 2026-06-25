require "../../../models/detector"

module Detector::Elixir
  # Detects Elixir command-line apps via OptionParser, System.argv, or the
  # optimus library. Never gates on bare System.get_env (Phoenix config).
  class Cli < Detector
    MARKERS = /\bOptionParser\.(?:parse|parse!|next)\b|\bSystem\.argv\b|\bOptimus\.new!?\b|\buse\s+Optimus\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ex") || filename.ends_with?(".exs")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ex") || filename.ends_with?(".exs")
    end

    def set_name
      @name = "elixir_cli"
    end
  end
end
