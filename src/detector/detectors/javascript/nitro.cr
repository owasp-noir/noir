require "../../../models/detector"

module Detector::Javascript
  class Nitro < Detector
    detector_for "js_nitro",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan instead of three.
    SIGNAL = Regex.union(
      /require\(['"]nitropack['"]\)/,
      /from ['"]nitropack['"]/,
      /defineNitroConfig\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      # Check for Nitro config files
      if filename.ends_with?("nitro.config.js") || filename.ends_with?("nitro.config.ts")
        return true
      end

      # Check for Nitro imports and patterns in JS/TS files
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") || filename.ends_with?(".cjs")) &&
         content_matches?(file_contents, SIGNAL)
        return true
      end

      false
    end
  end
end
