require "../../../models/detector"

module Detector::Go
  class GoRestful < Detector
    IMPORT_MARKER = "github.com/emicklei/go-restful"

    # Detect from `go.mod` (whole-repo scans) AND any `.go` file that
    # imports go-restful, so a sub-directory whose `go.mod` lives higher up
    # is still recognized when scanned on its own. The analyzer re-gates
    # every file on the same marker, so this can't over-extract.
    def detect(filename : String, file_contents : String) : Bool
      return true if (filename.includes? "go.mod") && file_contents.includes?(IMPORT_MARKER)
      return true if filename.ends_with?(".go") && file_contents.includes?(IMPORT_MARKER)
      false
    end

    def applicable?(filename : String) : Bool
      filename.includes?("go.mod") || filename.ends_with?(".go")
    end

    def set_name
      @name = "go_restful"
    end
  end
end
