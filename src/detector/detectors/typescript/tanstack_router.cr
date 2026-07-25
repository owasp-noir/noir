require "../../../models/detector"

module Detector::Typescript
  class TanstackRouter < Detector
    detector_for "ts_tanstack_router",
      extensions: %w[.ts .tsx .cts .mts .js .jsx .cjs .mjs],
      basenames: %w[package.json tsconfig.json]

    # Single precompiled alternation — one PCRE2 scan instead of eight.
    SIGNAL = Regex.union(
      /import.*from ['"]@tanstack\/react-router['"]/,
      /import.*from ['"]@tanstack\/router['"]/,
      /require\(['"]@tanstack\/react-router['"]\)/,
      /require\(['"]@tanstack\/router['"]\)/,
      /createFileRoute\s*\(/,
      /createRootRoute\s*\(/,
      /createRoute\s*\(/,
      /createRouter\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
