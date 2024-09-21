require "../../../models/detector"

module Detector::Elixir
  class Phoenix < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("ElixirPhoenix")
      check = check && filename.includes?("mix.exs")

      check
    end

    def set_name
      @name = "elixir_phoenix"
    end
  end
end
