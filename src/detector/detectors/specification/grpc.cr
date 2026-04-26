require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Grpc < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".proto")
        if file_contents.includes?("service") || file_contents.includes?("rpc")
          locator = CodeLocator.instance
          locator.push("grpc-proto", filename)
          return true
        end
      end

      false
    end

    def set_name
      @name = "grpc"
    end

    # Records every matching `.proto` path in `CodeLocator` for the
    # analyzer pass. Must keep running after the first match so all
    # service files get registered.
    def idempotent? : Bool
      false
    end
  end
end
