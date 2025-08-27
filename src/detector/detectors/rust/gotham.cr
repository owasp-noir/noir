require "../../../models/detector"

module Detector::Rust
  class Gotham < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("gotham")
      check = check && file_contents.includes?("dependencies")
      check = check && filename.includes?("Cargo.toml")

      check
    end

    def set_name
      @name = "rust_gotham"
    end
  end
end
