require "../../../models/detector"

module Detector::Javascript
  # Convex names itself in package.json; its functions import from
  # `convex/server` (`httpRouter`, `query`, `mutation`).
  class Convex < Detector
    detector_for "js_convex",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /"convex"\s*:|(?:\bfrom\s*|\brequire\s*\(\s*)['"]convex\/server['"]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("convex")
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
