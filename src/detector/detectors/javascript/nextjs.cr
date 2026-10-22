require "../../../models/detector"

module Detector::Javascript
  class Nextjs < Detector
    detector_for "js_nextjs",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # Single-pass union of the four Next.js import forms (`require("next")`,
    # `require("next/...")`, `from "next"`, `from "next/..."`) — previously
    # four separate whole-file scans per JS/TS source.
    NEXT_IMPORT = /require\(['"]next(?:\/[^'"]+)?['"]\)|from\s+['"]next(?:\/[^'"]+)?['"]/

    # The named HTTP-verb export an App Router `route.{js,ts}` must declare
    # to serve anything, in the forms Next.js accepts: `export async
    # function GET`, `export const POST = ...`, and the destructured
    # `export const { POST } = serve(...)` a handler factory returns.
    ROUTE_HANDLER_EXPORT = /\bexport\s+(?:async\s+)?(?:function|const|let|var)?\s*\{?\s*(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b/

    def detect(filename : String, file_contents : String) : Bool
      # Check for Next.js config files
      if filename.ends_with?("next.config.js") ||
         filename.ends_with?("next.config.ts") ||
         filename.ends_with?("next.config.mjs") ||
         filename.ends_with?("next.config.cjs")
        return true
      end

      # Check package.json containing "next" dependency
      if filename.ends_with?("package.json") &&
         file_contents.match(/"next"\s*:\s*"[^"]+"/)
        return true
      end

      # Pages Router API routes: /pages/api/**/*.{js,ts,jsx,tsx}
      #
      # Path alone isn't enough — Astro / SvelteKit / etc. can have
      # files under `src/pages/api/` that aren't Next.js. Require a
      # Next.js-specific content signal (`next` import or one of the
      # Next.js API request/response type names) so the same file
      # layout in another framework doesn't misidentify the project.
      if filename.includes?("/pages/api/") &&
         (filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
         filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
         filename.ends_with?(".mjs")) &&
         next_js_content_signal?(file_contents)
        return true
      end

      # App Router route handlers: /app/**/route.{js,ts}
      #
      # `app` is an ordinary directory name — the project's own documented
      # Docker command mounts the repo at `-w /app` — so this matches the
      # base-relative path, and demands a content signal the same way the
      # Pages Router branch above does. A bare `route.ts` under some
      # `app/` directory is not on its own a Next.js marker; a route
      # handler additionally exports a named HTTP verb or speaks to the
      # `Next*` request/response types.
      if base_relative_path(filename).includes?("/app/") &&
         (filename.ends_with?("/route.js") || filename.ends_with?("/route.ts") ||
         filename.ends_with?("/route.jsx") || filename.ends_with?("/route.tsx") ||
         filename.ends_with?("/route.mjs")) &&
         (next_js_content_signal?(file_contents) ||
         content_matches?(file_contents, ROUTE_HANDLER_EXPORT))
        return true
      end

      # Next.js imports in JS/TS source files
      if (filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
         filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
         filename.ends_with?(".mjs")) &&
         content_matches?(file_contents, NEXT_IMPORT)
        return true
      end

      false
    end

    private def next_js_content_signal?(content : String) : Bool
      content.includes?("from \"next\"") ||
        content.includes?("from 'next'") ||
        content.includes?("from \"next/") ||
        content.includes?("from 'next/") ||
        content.includes?("require(\"next\")") ||
        content.includes?("require('next')") ||
        content.includes?("require(\"next/") ||
        content.includes?("require('next/") ||
        content.includes?("NextApiRequest") ||
        content.includes?("NextApiResponse") ||
        content.includes?("NextRequest") ||
        content.includes?("NextResponse")
    end
  end
end
