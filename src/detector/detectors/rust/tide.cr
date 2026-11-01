require "../../../models/detector"

module Detector::Rust
  class Tide < Detector
    detector_for "rust_tide", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    # A `tide` dependency key (`tide = "1"`, `tide.workspace = true`,
    # `[dependencies.tide]`), not a mention in a comment or a sibling crate.
    # Same key shape as `RustEngine#cargo_dependency_re`, which gates the analyzer
    # to crates that really depend on it; a looser detector runs the analyzer on a
    # manifest the gate then waves every `.rs` file through for.
    CARGO_DEP_RE = /^\s*(?:tide\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.tide\])/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && file_contents.matches?(CARGO_DEP_RE)
    end
  end
end
