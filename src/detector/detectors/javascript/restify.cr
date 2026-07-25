require "../../../models/detector"

module Detector::Javascript
  class Restify < Detector
    detector_for "js_restify",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

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
  end
end
