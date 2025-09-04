require "../../../models/detector"

module Detector::Elixir
  class Plug < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check if this is a mix.exs file with Plug dependency
      if filename.includes?("mix.exs")
        return file_contents.includes?("{:plug,") || file_contents.includes?("plug:")
      end

      # Check for Plug-specific patterns in Elixir files
      if filename.ends_with?(".ex") || filename.ends_with?(".exs")
        # Look for Plug router modules or plug usage
        return file_contents.includes?("use Plug.Router") ||
          file_contents.includes?("plug :match") ||
          file_contents.includes?("plug :dispatch") ||
          file_contents.includes?("Plug.Router") ||
          file_contents.includes?("import Plug.") ||
          file_contents.includes?("forward ") && file_contents.includes?("do:")
      end

      false
    end

    def set_name
      @name = "elixir_plug"
    end
  end
end
