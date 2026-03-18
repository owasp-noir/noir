require "../../../models/detector"

module Detector::Javascript
  class Hono < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") ||
         filename.ends_with?(".jsx") || filename.ends_with?(".tsx") || filename.ends_with?(".cjs")) &&
         (file_contents.match(/require\(['"]hono['"]\)/) ||
         file_contents.match(/from ['"]hono['"]/) ||
         file_contents.match(/new\s+Hono\s*\(/))
        true
      else
        false
      end
    end

    def set_name
      @name = "js_hono"
    end
  end
end
