require "../../../models/detector"

module Detector::Javascript
  class Fresh < Detector
    detector_for "js_fresh",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    FRESH_MARKER = /\$fresh\//

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # Fresh project markers — the project lives on Deno, so the
      # canonical signals are `deno.json` / `deno.jsonc` referencing
      # `$fresh/` and `fresh.config.{ts,js}` files.
      if base == "fresh.config.ts" || base == "fresh.config.js" ||
         base == "main.ts" && content_matches?(file_contents, FRESH_MARKER)
        return true
      end

      if (base == "deno.json" || base == "deno.jsonc") &&
         content_matches?(file_contents, FRESH_MARKER)
        return true
      end

      # Source-side: Fresh handlers / pages import from `$fresh/`.
      if (filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
         filename.ends_with?(".js") || filename.ends_with?(".jsx")) &&
         content_matches?(file_contents, FRESH_MARKER)
        return true
      end

      false
    end
  end
end
