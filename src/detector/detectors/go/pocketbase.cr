require "../../../models/detector"

module Detector::Go
  class Pocketbase < Detector
    detector_for "go_pocketbase", extensions: %w[.go], path_segments: %w[go.mod]

    # Pocketbase apps are full Go programs that import the
    # framework's own `tools/router` package. The framework repo
    # itself self-references via the same path so the marker
    # works whether you're scanning a user app or the upstream.
    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, "github.com/pocketbase/pocketbase") ||
        (filename.ends_with?(".go") && file_contents.includes?("pocketbase/tools/router"))
    end
  end
end
