require "../../../models/detector"

module Detector::Go
  class GoZero < Detector
    IMPORT_MARKER = "github.com/zeromicro/go-zero"

    # One JIT-compiled scan per file instead of a Rabin-Karp walk;
    # every `.go` in the tree reaches this marker check.
    IMPORT_PATTERN = Regex.union(IMPORT_MARKER)

    # Detect from `go.mod` (whole-repo scans) AND any `.go` file that
    # imports go-zero. The `.go` path lets a microservice sub-directory
    # (e.g. `service/order/api`, whose `go.mod` lives at the monorepo
    # root) still be recognized when scanned on its own. The analyzer
    # re-gates every file on the same marker, so this can't over-extract.
    def detect(filename : String, file_contents : String) : Bool
      return true if (filename.includes? "go.mod") && content_matches?(file_contents, IMPORT_PATTERN)
      return true if filename.ends_with?(".go") && content_matches?(file_contents, IMPORT_PATTERN)
      false
    end

    def applicable?(filename : String) : Bool
      filename.includes?("go.mod") || filename.ends_with?(".go")
    end

    def set_name
      @name = "go_gozero"
    end
  end
end
