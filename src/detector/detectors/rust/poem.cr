require "../../../models/detector"

module Detector::Rust
  class Poem < Detector
    detector_for "rust_poem", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?("Cargo.toml")

      check = file_contents.match(/^\s*poem(-openapi)?\s*=\s*/m)
      check = !check.nil? && file_contents.includes?("dependencies")

      check
    end
  end
end
