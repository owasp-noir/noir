require "../../../models/detector"

module Detector::Javascript
  # React Router v7 framework mode (the Remix successor). Every
  # `@react-router/*` package — `dev`, `node`, `serve`, `fs-routes` — is
  # framework-mode tooling; library mode ships as plain `react-router` /
  # `react-router-dom`, which is a client-side SPA and serves no endpoints.
  class ReactRouter < Detector
    detector_for "js_react_router",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /@react-router\//

    def detect(filename : String, file_contents : String) : Bool
      return true if File.basename(filename).starts_with?("react-router.config.")

      # package.json, `vite.config.*` (the `@react-router/dev/vite` plugin)
      # and `app/routes.ts` (`@react-router/dev/routes`) all name the scope.
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
