require "../../../models/detector"

module Detector::Javascript
  class Remix < Detector
    PACKAGE_MARKER = /@remix-run\//
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

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_remix"
    end
  end
end
