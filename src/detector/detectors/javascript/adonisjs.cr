require "../../../models/detector"

module Detector::Javascript
  class Adonisjs < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `package.json` listing AdonisJS as a dependency.
      if base == "package.json" &&
         (file_contents.includes?("@adonisjs/core") ||
         file_contents.includes?("\"adonis-")) # legacy adonis-* packages
        return true
      end

      # `ace.js` is the AdonisJS CLI bootstrap — present in every
      # project root.
      return true if base == "ace.js" || base == "ace"

      # Source-side markers — handlers / route files import the v6
      # service-locator router or the v5 IoC alias.
      if (filename.ends_with?(".ts") || filename.ends_with?(".js") ||
         filename.ends_with?(".mjs")) &&
         (file_contents.includes?("@adonisjs/core") ||
         file_contents.includes?("@ioc:Adonis"))
        return true
      end

      false
    end

    def set_name
      @name = "js_adonisjs"
    end
  end
end
