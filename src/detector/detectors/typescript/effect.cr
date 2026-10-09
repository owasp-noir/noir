require "../../../models/detector"

module Detector::Typescript
  class Effect < Detector
    detector_for "ts_effect", extensions: %w[.ts .tsx .mts .cts .js .jsx .mjs .cjs]

    # The package root or an HttpApi subpath (`@effect/platform/HttpApiEndpoint`).
    IMPORT_RE = /(?:from\s*|require\(\s*)['"](?:@effect\/platform(?:\/HttpApi\w*)?|effect\/unstable\/httpapi(?:\/\w+)?)['"]/

    # `@effect/platform` is also the home of Effect's HTTP *client*, file
    # system and worker modules, so a dependency alone says nothing; the
    # HttpApi server DSL is what declares routes.
    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("HttpApiEndpoint")

      file_contents.matches?(IMPORT_RE)
    end
  end
end
