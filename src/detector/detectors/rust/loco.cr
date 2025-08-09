require "../../../models/detector"

module Detector::Rust
  class Loco < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("loco-rs")
      check = check && file_contents.includes?("dependencies")
      check = check && filename.includes?("Cargo.toml")

      check
    end

    def set_name
      @name = "rust_loco"
    end
  end
end
