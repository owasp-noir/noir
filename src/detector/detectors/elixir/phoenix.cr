require "../../../models/detector"

module Detector::Elixir
  class Phoenix < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("mix.exs")

      file_contents.includes?("ElixirPhoenix")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ex") || filename.ends_with?(".exs") || File.basename(filename) == "mix.exs"
    end

    def set_name
      @name = "elixir_phoenix"
    end
  end
end
