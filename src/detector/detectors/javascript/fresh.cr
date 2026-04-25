require "../../../models/detector"

module Detector::Javascript
  class Fresh < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # Fresh project markers — the project lives on Deno, so the
      # canonical signals are `deno.json` / `deno.jsonc` referencing
      # `$fresh/` and `fresh.config.{ts,js}` files.
      if base == "fresh.config.ts" || base == "fresh.config.js" ||
         base == "main.ts" && file_contents.includes?("$fresh/")
        return true
      end

      if (base == "deno.json" || base == "deno.jsonc") &&
         file_contents.includes?("$fresh/")
        return true
      end

      # Source-side: Fresh handlers / pages import from `$fresh/`.
      if (filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
         filename.ends_with?(".js") || filename.ends_with?(".jsx")) &&
         file_contents.includes?("$fresh/")
        return true
      end

      false
    end

    def set_name
      @name = "js_fresh"
    end
  end
end
