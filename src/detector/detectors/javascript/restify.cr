require "../../../models/detector"

module Detector::Javascript
  class Restify < Detector
    # `.js` accepts either quoting of the require; `.ts` only the double-quoted
    # form, which is how this detector has always behaved.
    JS_MARKERS = Regex.union("require('restify')", "require(\"restify\")")
    TS_MARKER  = /require\("restify"\)/

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".js")
        content_matches?(file_contents, JS_MARKERS)
      elsif filename.ends_with?(".ts")
        content_matches?(file_contents, TS_MARKER)
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_restify"
    end
  end
end
