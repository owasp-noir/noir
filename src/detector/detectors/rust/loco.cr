require "../../../models/detector"

module Detector::Rust
  class Loco < Detector
    detector_for "rust_loco", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      check = file_contents.includes?("loco-rs")
      check = check && file_contents.includes?("dependencies")

      check
    end
  end
end
