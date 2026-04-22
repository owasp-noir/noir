require "../../../models/detector"

module Detector::Rust
  class Poem < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      check = file_contents.includes?("poem")
      check = check && file_contents.includes?("dependencies")

      check
    end

    def set_name
      @name = "rust_poem"
    end
  end
end
