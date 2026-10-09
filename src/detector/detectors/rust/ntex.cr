require "../../../models/detector"

module Detector::Rust
  class Ntex < Detector
    detector_for "rust_ntex", basenames: %w[Cargo.toml]

    # `ntex = "2"`, `ntex = { workspace = true }`, `ntex.workspace = true` and
    # `[dependencies.ntex]`. Anchored on the key so the sibling crates
    # (`ntex-mqtt`, `ntex-bytes`, `ntex-files`) don't count on their own.
    # Same key shape as `RustEngine#cargo_dependency_re`, which the analyzer
    # uses to gate files to ntex crates.
    CARGO_DEP_RE = /^\s*(?:ntex\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.ntex\])/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless File.basename(filename) == "Cargo.toml"

      file_contents.includes?("dependencies") && file_contents.matches?(CARGO_DEP_RE)
    end
  end
end
