require "../../../models/detector"

module Detector::Javascript
  class Elysia < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `package.json` listing elysia as a dependency.
      if base == "package.json" && file_contents.includes?("\"elysia\"")
        return true
      end

      # Source-side markers — Elysia handlers always import from
      # `elysia`. Bun's TS-first toolchain means `.ts` is the
      # dominant extension; `.js` / `.mjs` are also valid.
      return false unless filename.ends_with?(".ts") ||
                          filename.ends_with?(".tsx") ||
                          filename.ends_with?(".js") ||
                          filename.ends_with?(".mjs")

      file_contents.includes?("from 'elysia'") ||
        file_contents.includes?("from \"elysia\"") ||
        file_contents.includes?("require('elysia')") ||
        file_contents.includes?("require(\"elysia\")")
    end

    def set_name
      @name = "js_elysia"
    end
  end
end
