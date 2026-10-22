require "../../../models/detector"

module Detector::Rust
  class Rocket < Detector
    detector_for "rust_rocket", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      check = filename.includes?("Cargo.toml")
      check = check && file_contents.includes?("rocket")
      check = check && file_contents.includes?("dependencies")

      check
    end
  end
end
