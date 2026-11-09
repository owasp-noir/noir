require "../../../models/detector"

module Detector::Typescript
  class Tsoa < Detector
    detector_for "ts_tsoa",
      extensions: %w[.ts],
      basenames: %w[package.json]

    PACKAGE_RE = /"(?:tsoa|@tsoa\/runtime)"\s*:/
    IMPORT_RE  = /(?:\bfrom|\brequire\s*\()\s*['"](?:tsoa|@tsoa\/runtime)['"]/

    def detect(filename : String, file_contents : String) : Bool
      package_json_or_ts_import?(filename, file_contents, PACKAGE_RE, IMPORT_RE)
    end
  end
end
