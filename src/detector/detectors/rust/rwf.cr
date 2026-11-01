require "../../../models/detector"
require "../../../miniparsers/cargo_dependency"

module Detector::Rust
  class Rwf < Detector
    detector_for "rust_rwf", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && Noir::CargoDependency.declares?(file_contents, "rwf")
    end
  end
end
