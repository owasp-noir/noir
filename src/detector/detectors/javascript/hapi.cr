require "../../../models/detector"

module Detector::Javascript
  class Hapi < Detector
    detector_for "js_hapi", extensions: %w[.js .mjs .cjs .jsx .ts .tsx], basenames: %w[package.json]

    MARKERS = Regex.union(
      "@hapi/hapi",
      "require('hapi')", "require(\"hapi\")",
      "from 'hapi'", "from \"hapi\"",
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") ||
                          filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") ||
                          filename.ends_with?(".ts")
      # Necessary condition for every marker below, which all spell `hapi`
      # literally; a memchr scan is far cheaper than the alternation regex.
      return false unless file_contents.includes?("hapi")
      content_matches?(file_contents, MARKERS)
    end
  end
end
