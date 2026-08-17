require "../../../models/detector"

module Detector::Javascript
  class Adonisjs < Detector
    detector_for "js_adonisjs",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json ace]

    PACKAGE_MARKERS = Regex.union("@adonisjs/core", "\"adonis-") # legacy adonis-* packages
    SOURCE_MARKERS  = Regex.union("@adonisjs/core", "@ioc:Adonis")

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `package.json` listing AdonisJS as a dependency.
      if base == "package.json" && content_matches?(file_contents, PACKAGE_MARKERS)
        return true
      end

      # `ace.js` is the AdonisJS CLI bootstrap — present in every
      # project root.
      return true if base == "ace.js" || base == "ace"

      # Source-side markers — handlers / route files import the v6
      # service-locator router or the v5 IoC alias.
      if (filename.ends_with?(".ts") || filename.ends_with?(".js") ||
         filename.ends_with?(".mjs")) &&
         content_matches?(file_contents, SOURCE_MARKERS)
        return true
      end

      false
    end
  end
end
