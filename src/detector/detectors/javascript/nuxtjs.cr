require "../../../models/detector"

module Detector::Javascript
  class Nuxtjs < Detector
    EVENT_HANDLER = /defineEventHandler/

    # Single precompiled alternation — one PCRE2 scan instead of six.
    SIGNAL = Regex.union(
      /require\(['"]nuxt['"]\)/,
      /import.*from ['"]nuxt['"]/,
      /defineNuxtConfig\s*\(/,
      /defineEventHandler\s*\(/,
      /from ['"]#app['"]/,
      /from ['"]@nuxt\//,
    )

    def detect(filename : String, file_contents : String) : Bool
      # Check for Nuxt config files
      if filename.ends_with?("nuxt.config.js") || filename.ends_with?("nuxt.config.ts")
        return true
      end

      # Check for Nuxt imports and patterns in JS/TS files
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts")) &&
         content_matches?(file_contents, SIGNAL)
        return true
      end

      # Nuxt 3 server routes live under `/server/api/` or
      # `/server/routes/`, but those paths are also used by
      # several Koa/Express projects (Outline, etc.) for plain
      # routers. Require the `defineEventHandler` call before
      # claiming the file for Nuxt — the strong import signals
      # above (defineNuxtConfig, @nuxt/..., bare `nuxt` import)
      # still catch projects that lack the directory layout.
      if (filename.includes?("/server/api/") || filename.includes?("/server/routes/")) &&
         (filename.ends_with?(".js") || filename.ends_with?(".ts") ||
         filename.ends_with?(".mjs") || filename.ends_with?(".mts")) &&
         content_matches?(file_contents, EVENT_HANDLER)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_nuxtjs"
    end
  end
end
