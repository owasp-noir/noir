require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Grpc < Detector
    # A gRPC service is defined by a `service Name { ... }` block. Matching that
    # structural marker — rather than the bare substrings "service"/"rpc", which
    # also occur in ordinary field names like `service_url` or `rpc_timeout` —
    # keeps message-only and config `.proto` files from being mislabeled as gRPC.
    SERVICE_BLOCK = /\bservice\s+\w+\s*\{/

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".proto") && file_contents.matches?(SERVICE_BLOCK)
        CodeLocator.instance.push("grpc-proto", filename)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".proto")
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
