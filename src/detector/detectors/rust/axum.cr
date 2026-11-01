require "../../../models/detector"

module Detector::Rust
  class Axum < Detector
    detector_for "rust_axum", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    # A `axum` dependency key (`axum = "1"`, `axum.workspace = true`,
    # `[dependencies.axum]`), not a mention in a comment or a sibling crate.
    # Same key shape as `RustEngine#cargo_dependency_re`, which gates the analyzer
    # to crates that really depend on it; a looser detector runs the analyzer on a
    # manifest the gate then waves every `.rs` file through for.
    CARGO_DEP_RE = /^\s*(?:axum\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.axum\])/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && file_contents.matches?(CARGO_DEP_RE)
    end
  end
end
