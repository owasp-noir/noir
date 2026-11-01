require "../../../models/detector"

module Detector::Rust
  class ActixWeb < Detector
    detector_for "rust_actix_web", extensions: %w[.rs], basenames: %w[Cargo.toml Cargo.lock]

    # A `actix-web` dependency key (`actix-web = "1"`, `actix-web.workspace = true`,
    # `[dependencies.actix-web]`), not a mention in a comment or a sibling crate.
    # Same key shape as `RustEngine#cargo_dependency_re`, which gates the analyzer
    # to crates that really depend on it; a looser detector runs the analyzer on a
    # manifest the gate then waves every `.rs` file through for.
    CARGO_DEP_RE = /^\s*(?:actix-web\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.actix-web\])/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      file_contents.includes?("dependencies") && file_contents.matches?(CARGO_DEP_RE)
    end
  end
end
