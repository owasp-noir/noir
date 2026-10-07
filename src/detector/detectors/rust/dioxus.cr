require "../../../models/detector"

module Detector::Rust
  class Dioxus < Detector
    detector_for "rust_dioxus", basenames: %w[Cargo.toml]

    # A `dioxus` dependency key, not a `dioxus_*` / `dioxus-*` companion crate.
    DEPENDENCY_RE = /^\s*(?:dioxus\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.dioxus\])/m

    def detect(filename : String, file_contents : String) : Bool
      File.basename(filename) == "Cargo.toml" && file_contents.matches?(DEPENDENCY_RE)
    end
  end
end
