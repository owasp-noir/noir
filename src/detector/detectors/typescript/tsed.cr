require "../../../models/detector"

module Detector::Typescript
  class Tsed < Detector
    detector_for "ts_tsed",
      extensions: %w[.ts],
      basenames: %w[package.json]

    # The routing packages, not every `@tsed/*` (a plain Express app can
    # pull in `@tsed/logger` alone).
    PACKAGE_RE = /"@tsed\/(?:common|schema|di|platform-[\w-]+)"\s*:/
    IMPORT_RE  = /(?:\bfrom|\brequire\s*\()\s*['"]@tsed\/(?:common|schema|di|platform-[\w-]+)['"]/

    def detect(filename : String, file_contents : String) : Bool
      package_json_or_ts_import?(filename, file_contents, PACKAGE_RE, IMPORT_RE)
    end
  end
end
