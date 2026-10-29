require "../../../models/detector"

module Detector::Javascript
  class Medusa < Detector
    detector_for "js_medusa",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # Quoted so `@medusajs/medusa-js` and `@medusajs/framework-utils` do not match.
    PACKAGE_MARKER = /"(?:@medusajs\/medusa|@medusajs\/framework)"\s*:/
    RUNTIME_KEYS   = %w[dependencies peerDependencies]
    PACKAGES       = ["@medusajs/medusa", "@medusajs/framework"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless File.basename(filename) == "package.json"
      return false unless content_matches?(file_contents, PACKAGE_MARKER)

      deps = JSON.parse(file_contents).as_h? || return false
      RUNTIME_KEYS.any? do |key|
        deps[key]?.try(&.as_h?).try { |table| PACKAGES.any? { |name| table.has_key?(name) } } || false
      end
    rescue JSON::ParseException
      false
    end
  end
end
