require "../../../models/detector"

module Detector::Go
  class ConnectRpc < Detector
    IMPORT_MARKER = "connectrpc.com/connect"

    # One JIT-compiled scan per file instead of a Rabin-Karp walk;
    # every `.go` in the tree reaches this marker check.
    IMPORT_PATTERN = Regex.union(IMPORT_MARKER)

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("go.mod") && content_matches?(file_contents, IMPORT_PATTERN)
        return true
      end
      if filename.ends_with?(".go") && content_matches?(file_contents, IMPORT_PATTERN)
        return true
      end
      false
    end

    def applicable?(filename : String) : Bool
      filename.includes?("go.mod") || filename.ends_with?(".go")
    end

    def set_name
      @name = "go_connect_rpc"
    end
  end
end
