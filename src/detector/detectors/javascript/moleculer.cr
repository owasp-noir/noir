require "../../../models/detector"

module Detector::Javascript
  # Moleculer names itself (and the `moleculer-web` gateway) in
  # package.json; services require or import either package.
  class Moleculer < Detector
    detector_for "js_moleculer",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /"moleculer(?:-web)?"\s*:|(?:\bfrom\s*|\brequire\s*\(\s*)['"]moleculer(?:-web)?['"]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("moleculer")
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
