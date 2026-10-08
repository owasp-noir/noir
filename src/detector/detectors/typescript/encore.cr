require "../../../models/detector"

module Detector::Typescript
  class Encore < Detector
    detector_for "ts_encore", extensions: %w[.ts .mts .cts], basenames: %w[package.json]

    IMPORT_RE = /from\s*['"]encore\.dev\//

    # An `encore.dev` dependency in package.json, or an `encore.dev/*` import.
    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("encore.dev")
      return file_contents.includes?("\"encore.dev\"") if File.basename(filename) == "package.json"

      file_contents.matches?(IMPORT_RE)
    end
  end
end
