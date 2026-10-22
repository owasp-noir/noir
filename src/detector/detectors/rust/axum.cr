require "../../../models/detector"

module Detector::Rust
  class Axum < Detector
    detector_for "rust_axum", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      check = file_contents.includes?("axum")
      check = check && file_contents.includes?("dependencies")

      check
    end
  end
end
