require "../../../models/detector"

module Detector::Javascript
  # Feathers.js (https://feathersjs.com) is a service-based, not
  # route-based, Node.js framework: `app.use('/messages', new
  # MessageService())` registers a *service*, and the framework
  # auto-generates the REST CRUD verbs for whichever of
  # find/get/create/update/patch/remove the service implements. The
  # `@feathersjs/*` scope is unique to this framework — there is no
  # risk of colliding with plain Express, which is what Feathers'
  # REST transport (`@feathersjs/express`) is layered on top of.
  class Feathers < Detector
    detector_for "js_feathers",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # `package.json` listing any `@feathersjs/*` package (feathers,
    # express, koa, socketio, authentication, transport-commons, ...)
    # as a dependency. The scope alone is unambiguous, so a broad
    # "any @feathersjs/<name> key" match is safe.
    PACKAGE_MARKER = /"@feathersjs\/[\w-]+"\s*:/

    # Source-side evidence: an import/require of any `@feathersjs/*`
    # module (including submodule specifiers like
    # `@feathersjs/express/rest`), the `feathers()` core factory call,
    # or `app.service(` — the one Feathers-specific API on the app
    # object that plain Express never has.
    SOURCE_MARKERS = Regex.union(
      /(?:require\(|from\s)['"]@feathersjs\/[\w.\/-]+['"]/,
      /\bfeathers\s*\(\s*\)/,
      /\.service\s*\(\s*['"][^'"]*['"]\s*\)/,
    )

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "package.json"
        return content_matches?(file_contents, PACKAGE_MARKER)
      end

      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") || filename.ends_with?(".ts") ||
                          filename.ends_with?(".tsx") || filename.ends_with?(".jsx")

      content_matches?(file_contents, SOURCE_MARKERS)
    end
  end
end
