require "../../../models/detector"

module Detector::Rust
  class Gotham < Detector
    detector_for "rust_gotham", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    # A `gotham` dependency key (`gotham = "1"`, `gotham.workspace = true`,
    # `[dependencies.gotham]`), not a mention in a comment or a sibling crate.
    # Same key shape as `RustEngine#cargo_dependency_re`, which gates the analyzer
    # to crates that really depend on it; a looser detector runs the analyzer on a
    # manifest the gate then waves every `.rs` file through for.
    CARGO_DEP_RE = /^\s*(?:gotham\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.gotham\])/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && file_contents.matches?(CARGO_DEP_RE)
    end
  end
end
