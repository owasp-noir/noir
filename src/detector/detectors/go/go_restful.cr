require "../../../models/detector"

module Detector::Go
  class GoRestful < Detector
    detector_for "go_restful", extensions: %w[.go], path_segments: %w[go.mod]

    IMPORT_MARKER = "github.com/emicklei/go-restful"

    # One JIT-compiled scan per file instead of a Rabin-Karp walk;
    # every `.go` in the tree reaches this marker check.
    IMPORT_PATTERN = Regex.union(IMPORT_MARKER)

    # Detect from `go.mod` (whole-repo scans) AND any `.go` file that
    # imports go-restful, so a sub-directory whose `go.mod` lives higher up
    # is still recognized when scanned on its own. The analyzer re-gates
    # every file on the same marker, so this can't over-extract.
    def detect(filename : String, file_contents : String) : Bool
      go_dependency?(filename, file_contents, IMPORT_PATTERN)
    end
  end
end
