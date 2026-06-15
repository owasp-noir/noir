require "../../../models/detector"

module Detector::Javascript
  class Nitro < Detector
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
         file_contents.matches?(SIGNAL)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_nitro"
    end
  end
end
