require "../../../models/detector"

module Detector::Javascript
  class Astro < Detector
    detector_for "js_astro",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    def detect(filename : String, file_contents : String) : Bool
      # `.astro` files are unmistakable.
      return true if filename.ends_with?(".astro")

      # `astro.config.{mjs,ts,js,cjs}` is the project marker.
      base = File.basename(filename)
      if base == "astro.config.mjs" || base == "astro.config.ts" ||
         base == "astro.config.js" || base == "astro.config.cjs"
        return true
      end

      # `package.json` listing astro as a dependency. Cheap substring
      # match — anything more clever (JSON parse) is overkill here.
      if base == "package.json" && file_contents.includes?("\"astro\"")
        return true
      end

      false
    end
  end
end
