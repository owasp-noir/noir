require "../../../models/detector"

module Detector::Rust
  class ActixWeb < Detector
    detector_for "rust_actix_web", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      check = file_contents.includes?("actix-web")
      check = check && file_contents.includes?("dependencies")

      check
    end
  end
end
