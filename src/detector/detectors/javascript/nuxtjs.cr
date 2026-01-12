require "../../../models/detector"

module Detector::Javascript
  class Nuxtjs < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for Nuxt config files
      if filename.ends_with?("nuxt.config.js") || filename.ends_with?("nuxt.config.ts")
        return true
      end

      # Check for Nuxt imports and patterns in JS/TS files
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts")) &&
         (file_contents.match(/require\(['"]nuxt['"]\)/) ||
         file_contents.match(/import.*from ['"]nuxt['"]/) ||
         file_contents.match(/defineNuxtConfig\s*\(/) ||
         file_contents.match(/defineEventHandler\s*\(/) ||
         file_contents.match(/from ['"]#app['"]/) ||
         file_contents.match(/from ['"]@nuxt\//))
        return true
      end

      # Check for server/api or server/routes directory patterns
      if (filename.includes?("/server/api/") || filename.includes?("/server/routes/")) &&
         (filename.ends_with?(".js") || filename.ends_with?(".ts") ||
         filename.ends_with?(".mjs") || filename.ends_with?(".mts"))
        return true
      end

      false
    end

    def set_name
      @name = "js_nuxtjs"
    end
  end
end
