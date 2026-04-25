require "../../../models/detector"

module Detector::Javascript
  class Nextjs < Detector
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
      if filename.includes?("/app/") &&
         (filename.ends_with?("/route.js") || filename.ends_with?("/route.ts") ||
         filename.ends_with?("/route.jsx") || filename.ends_with?("/route.tsx") ||
         filename.ends_with?("/route.mjs"))
        return true
      end

      # Next.js imports in JS/TS source files
      if (filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
         filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
         filename.ends_with?(".mjs")) &&
         (file_contents.match(/require\(['"]next['"]\)/) ||
         file_contents.match(/require\(['"]next\/[^'"]+['"]\)/) ||
         file_contents.match(/from\s+['"]next['"]/) ||
         file_contents.match(/from\s+['"]next\/[^'"]+['"]/))
        return true
      end

      false
    end

    def set_name
      @name = "js_nextjs"
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
