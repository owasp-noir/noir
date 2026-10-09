require "../../../models/detector"

module Detector::Typescript
  class RoutingControllers < Detector
    detector_for "ts_routing_controllers",
      extensions: %w[.ts],
      basenames: %w[package.json]

    PACKAGE_RE = /"routing-controllers"\s*:/
    IMPORT_RE  = /(?:\bfrom|\brequire\s*\()\s*['"]routing-controllers['"]/

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return content_matches?(file_contents, PACKAGE_RE)
      end

      filename.ends_with?(".ts") && content_matches?(file_contents, IMPORT_RE)
    end
  end
end
