require "../../../models/detector"

module Detector::Rust
  class Leptos < Detector
    detector_for "rust_leptos", basenames: %w[Cargo.toml]

    # A `leptos` dependency key, not a `leptos_*` / `leptos-*` companion crate.
    DEPENDENCY_RE = /^\s*(?:leptos\s*[=.]|\[(?:[\w.-]+\.)?dependencies\.leptos\])/m

    def detect(filename : String, file_contents : String) : Bool
      File.basename(filename) == "Cargo.toml" && file_contents.matches?(DEPENDENCY_RE)
    end
  end
end
