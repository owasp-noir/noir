require "../../../models/detector"

module Detector::Javascript
  class Nitro < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for Nitro config files
      if filename.ends_with?("nitro.config.js") || filename.ends_with?("nitro.config.ts")
        return true
      end

      # Check for Nitro imports and patterns in JS/TS files
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") || filename.ends_with?(".cjs")) &&
         (file_contents.match(/require\(['"]nitropack['"]\)/) ||
         file_contents.match(/from ['"]nitropack['"]/) ||
         file_contents.match(/defineNitroConfig\s*\(/))
        return true
      end

      false
    end

    def set_name
      @name = "js_nitro"
    end
  end
end
