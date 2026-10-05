require "../../../models/detector"

module Detector::Javascript
  class Remix < Detector
    detector_for "js_remix",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # Remix v2's own packages. The `@remix-run/` scope alone is not a Remix
    # app: React Router and Remix 3 publish utilities under it
    # (`@remix-run/node-fetch-server`, `@remix-run/router`), and React
    # Router v7 apps that pull one in read as Remix.
    PACKAGE_MARKER = /@remix-run\/(?:dev|react|node|serve|server-runtime|cloudflare|cloudflare-pages|cloudflare-workers|deno|express|architect)(?![\w-])/
    VITE_MARKER    = /@remix-run\/dev/

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # Remix project markers — `remix.config.{js,ts,mjs,cjs}` and
      # `vite.config.*` with `@remix-run/dev` import (Remix 2 ships
      # via Vite). The `package.json` `@remix-run/*` listing covers
      # both.
      if base == "remix.config.js" || base == "remix.config.ts" ||
         base == "remix.config.mjs" || base == "remix.config.cjs"
        return true
      end

      if base == "package.json" && content_matches?(file_contents, PACKAGE_MARKER)
        return true
      end

      # `vite.config.*` carrying `@remix-run/dev` confirms a
      # Remix 2 / Vite project even when package.json is far away.
      if (base.starts_with?("vite.config.") || base.starts_with?("remix.")) &&
         content_matches?(file_contents, VITE_MARKER)
        return true
      end

      # Source-side markers — Remix routes commonly import from
      # `@remix-run/node` / `@remix-run/cloudflare` / `@remix-run/react`.
      if (filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
         filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
         filename.ends_with?(".mjs")) &&
         content_matches?(file_contents, PACKAGE_MARKER)
        return true
      end

      false
    end
  end
end
