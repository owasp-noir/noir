require "../../../models/detector"

module Detector::Javascript
  class Elysia < Detector
    detector_for "js_elysia",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /"elysia"/
    SOURCE_MARKERS = Regex.union(
      "from 'elysia'", "from \"elysia\"",
      "require('elysia')", "require(\"elysia\")",
    )

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `package.json` listing elysia as a dependency.
      if base == "package.json" && content_matches?(file_contents, PACKAGE_MARKER)
        return true
      end

      # Source-side markers — Elysia handlers always import from
      # `elysia`. Bun's TS-first toolchain means `.ts` is the
      # dominant extension; `.js` / `.mjs` are also valid.
      return false unless filename.ends_with?(".ts") ||
                          filename.ends_with?(".tsx") ||
                          filename.ends_with?(".js") ||
                          filename.ends_with?(".mjs")

      content_matches?(file_contents, SOURCE_MARKERS)
    end
  end
end
