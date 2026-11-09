require "../../../models/detector"

module Detector::Typescript
  class RoutingControllers < Detector
    detector_for "ts_routing_controllers",
      extensions: %w[.ts],
      basenames: %w[package.json]

    PACKAGE_RE = /"routing-controllers"\s*:/
    IMPORT_RE  = /(?:\bfrom|\brequire\s*\()\s*['"]routing-controllers['"]/

    def detect(filename : String, file_contents : String) : Bool
      package_json_or_ts_import?(filename, file_contents, PACKAGE_RE, IMPORT_RE)
    end
  end
end
