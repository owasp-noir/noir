require "../../../models/detector"

module Detector::Javascript
  class Sails < Detector
    detector_for "js_sails",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # `package.json` listing Sails as a dependency. Sails apps always
    # depend on the `sails` npm package directly (it is the framework
    # entry point, not a plugin), so a dependency-map hit is a reliable
    # project-level signal even when the file that would carry a source
    # marker (`app.js`) has been customized or renamed.
    PACKAGE_MARKERS = /"sails"\s*:\s*"/

    # Source-side markers. `sails.lift(` is the canonical bootstrap call
    # every generated `app.js`/`server.js` carries; the require/import
    # forms cover apps that construct the app object under a different
    # name before lifting it.
    SOURCE_MARKERS = Regex.union(
      "require('sails')", "require(\"sails\")",
      "from 'sails'", "from \"sails\"",
      "sails.lift(",
    )

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "package.json"
        return content_matches?(file_contents, PACKAGE_MARKERS)
      end

      if filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
         filename.ends_with?(".cjs") || filename.ends_with?(".ts")
        return content_matches?(file_contents, SOURCE_MARKERS)
      end

      false
    end
  end
end
