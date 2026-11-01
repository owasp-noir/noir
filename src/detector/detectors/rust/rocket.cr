require "../../../models/detector"

module Detector::Rust
  class Rocket < Detector
    detector_for "rust_rocket", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    # A `rocket` dependency key (`rocket = "1"`, `rocket.workspace = true`,
    # `[dependencies.rocket]`), not a mention in a comment or a sibling crate.
    # Same key shape as `RustEngine#cargo_dependency_re`, which gates the analyzer
    # to crates that really depend on it; a looser detector runs the analyzer on a
    # manifest the gate then waves every `.rs` file through for.
    CARGO_DEP_RE = /^\s*(?:rocket\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.rocket\])/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && file_contents.matches?(CARGO_DEP_RE)
    end
  end
end
