require "../../../models/detector"
require "../../../miniparsers/cargo_dependency"

module Detector::Rust
  class Axum < Detector
    detector_for "rust_axum", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && Noir::CargoDependency.declares?(file_contents, "axum")
    end
  end
end
