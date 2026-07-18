require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class OpenRpc < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      return false unless file_contents.includes?("openrpc")
      return false unless filename.ends_with?(".json")

      begin
        data = JSON.parse(file_contents)
        version = data["openrpc"].as_s
        if version.starts_with?("1.")
          check = true
          locator = CodeLocator.instance
          locator.push("openrpc-json", filename)
        end
      rescue e
        logger.debug "OpenRPC JSON detection failed for #{filename}: #{e}"
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json")
    end

    def set_name
      @name = "openrpc"
    end

    # Registers every OpenRPC spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    def idempotent? : Bool
      false
    end
  end
end
