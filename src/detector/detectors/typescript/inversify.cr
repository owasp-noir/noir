require "../../../models/detector"

module Detector::Typescript
  class Inversify < Detector
    detector_for "ts_inversify",
      extensions: %w[.ts],
      basenames: %w[package.json]

    PACKAGE_RE = /"inversify-express-utils"\s*:/
    IMPORT_RE  = /(?:\bfrom|\brequire\s*\()\s*['"]inversify-express-utils['"]/

    def detect(filename : String, file_contents : String) : Bool
      package_json_or_ts_import?(filename, file_contents, PACKAGE_RE, IMPORT_RE)
    end
  end
end
