require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Grpc < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".proto")
        if file_contents.includes?("syntax") && (file_contents.includes?("service") || file_contents.includes?("rpc"))
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
  end
end
