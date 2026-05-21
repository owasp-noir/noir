require "../../../models/detector"

module Detector::Go
  class ConnectRpc < Detector
    IMPORT_MARKER = "connectrpc.com/connect"

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("go.mod") && file_contents.includes?(IMPORT_MARKER)
        return true
      end
      if filename.ends_with?(".go") && file_contents.includes?(IMPORT_MARKER)
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
