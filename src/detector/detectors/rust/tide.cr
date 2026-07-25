require "../../../models/detector"

module Detector::Rust
  class Tide < Detector
    detector_for "rust_tide", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      check = file_contents.includes?("tide")
      check = check && file_contents.includes?("dependencies")

      check
    end
  end
end
