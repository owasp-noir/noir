require "../../../models/detector"

module Detector::Javascript
  # SolidStart names its package in package.json, the `app.config.*`
  # (`@solidjs/start/config`) and the client/server entries; pre-1.0 apps
  # depend on `solid-start`. Plain
  # `solid-js` and `@solidjs/router` are client-side and serve nothing.
  class Solidstart < Detector
    detector_for "js_solidstart",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /@solidjs\/start\b|"solid-start"/

    def detect(filename : String, file_contents : String) : Bool
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
