require "../../../models/detector"

module Detector::Javascript
  class Elysia < Detector
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

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_elysia"
    end
  end
end
