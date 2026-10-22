require "../../../models/detector"

module Detector::Javascript
  # Qwik City ships as `@builder.io/qwik-city` (Qwik 1) and was renamed
  # `@qwik.dev/router` for Qwik 2. Core `@builder.io/qwik` alone is a
  # client component library with no router.
  class QwikCity < Detector
    detector_for "js_qwik_city",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /@builder\.io\/qwik-city\b|@qwik\.dev\/router\b/

    def detect(filename : String, file_contents : String) : Bool
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
