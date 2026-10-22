require "../../../models/detector"

module Detector::Javascript
  class Nuxtjs < Detector
    detector_for "js_nuxtjs",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx .mts .cts],
      basenames: %w[package.json]

    PACKAGE_DEP      = /"nuxt"\s*:/
    CONFIG_BASENAMES = %w[nuxt.config.js nuxt.config.ts nuxt.config.mjs nuxt.config.mts nuxt.config.cjs]

    # Single precompiled alternation — one PCRE2 scan instead of five.
    # `defineEventHandler` is deliberately absent: it is the h3 primitive
    # every Nitro, Analog and SolidStart server route uses, so on its own it
    # claimed plain Nitro projects for Nuxt and reported each
    # `server/routes` file twice.
    SIGNAL = Regex.union(
      /require\(['"]nuxt['"]\)/,
      /import.*from ['"]nuxt['"]/,
      /defineNuxtConfig\s*\(/,
      /from ['"]#app['"]/,
      /from ['"]@nuxt\//,
    )

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)
      return true if CONFIG_BASENAMES.includes?(base)

      # `package.json` listing nuxt as a dependency (a `"nuxt":` key, so a
      # `"keywords": ["nuxt"]` entry does not count).
      return content_matches?(file_contents, PACKAGE_DEP) if base == "package.json"

      # Check for Nuxt imports and patterns in JS/TS files
      (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts")) &&
        (file_contents.includes?("nuxt") || file_contents.includes?("Nuxt") || file_contents.includes?("#app")) &&
        content_matches?(file_contents, SIGNAL)
    end
  end
end
