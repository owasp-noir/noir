require "../../../models/detector"

module Detector::Javascript
  # HonoX names itself in package.json and in its `honox/factory`,
  # `honox/server` and `honox/vite` imports.
  class Honox < Detector
    detector_for "js_honox",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    MARKER = /"honox"|['"]honox\//

    def detect(filename : String, file_contents : String) : Bool
      content_matches?(file_contents, MARKER)
    end
  end
end
