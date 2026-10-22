require "../../../models/detector"

module Detector::Typescript
  class Orpc < Detector
    detector_for "ts_orpc", extensions: %w[.ts .tsx .mts .cts .js .jsx .mjs .cjs], basenames: %w[package.json]

    PACKAGE_RE = /"@orpc\/(?:server|contract)"/
    IMPORT_RE  = /(?:from\s*|require\(\s*)['"]@orpc\/(?:server|contract)['"]/

    # An `@orpc/server` / `@orpc/contract` dependency or import.
    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("@orpc/")
      return file_contents.matches?(PACKAGE_RE) if File.basename(filename) == "package.json"

      file_contents.matches?(IMPORT_RE)
    end
  end
end
