require "../../../models/detector"

module Detector::Javascript
  class Hapi < Detector
    detector_for "js_hapi", extensions: %w[.js .mjs .cjs .jsx .ts .tsx], basenames: %w[package.json]

    MARKERS = Regex.union(
      "@hapi/hapi",
      "require('hapi')", "require(\"hapi\")",
      "from 'hapi'", "from \"hapi\"",
    )
    # A Glue or haute-couture app never imports hapi in code; its
    # package.json still depends on it at runtime (not as a dev tool).
    PACKAGE_MARKER          = /"(?:@hapi\/hapi|hapi)"\s*:/
    RUNTIME_DEPENDENCY_KEYS = %w[dependencies peerDependencies]

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return false unless content_matches?(file_contents, PACKAGE_MARKER)
        deps = JSON.parse(file_contents).as_h? || return false
        return RUNTIME_DEPENDENCY_KEYS.any? do |key|
          deps[key]?.try(&.as_h?).try { |h| h.has_key?("hapi") || h.has_key?("@hapi/hapi") } || false
        end
      end
      return false unless filename.ends_with?(".js") ||
                          filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") ||
                          filename.ends_with?(".ts")
      # Necessary condition for every marker below, which all spell `hapi`
      # literally; a memchr scan is far cheaper than the alternation regex.
      return false unless file_contents.includes?("hapi")
      content_matches?(file_contents, MARKERS)
    rescue JSON::ParseException
      false
    end
  end
end
