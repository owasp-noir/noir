require "../../../models/detector"

module Detector::Typescript
  class TsRest < Detector
    detector_for "ts_tsrest", extensions: %w[.ts .tsx .mts .cts .js .jsx .mjs .cjs], basenames: %w[package.json]

    IMPORT_RE = /(?:from\s*|require\(\s*)['"]@ts-rest\/core['"]/

    # An `@ts-rest/core` dependency in package.json, or an import of it.
    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("@ts-rest/core")
      return file_contents.includes?("\"@ts-rest/core\"") if File.basename(filename) == "package.json"

      file_contents.matches?(IMPORT_RE)
    end
  end
end
