require "../../../models/detector"

module Detector::Javascript
  class Sveltekit < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `svelte.config.{js,ts,mjs,cjs}` is the project marker — every
      # SvelteKit project has one to register the kit adapter.
      if base == "svelte.config.js" || base == "svelte.config.ts" ||
         base == "svelte.config.mjs" || base == "svelte.config.cjs"
        return true
      end

      # `package.json` listing the kit dependency — `@sveltejs/kit`
      # is the canonical name; the legacy `svelte-kit` form is rare
      # but harmless to also accept.
      if base == "package.json" &&
         (file_contents.includes?("@sveltejs/kit") ||
         file_contents.includes?("\"svelte-kit\""))
        return true
      end

      # `+server.{js,ts,mjs}` files anywhere under a `routes`
      # directory pin the project as SvelteKit. The pages-only case
      # is covered by the config / package.json checks.
      if (base.starts_with?("+server.") || base.starts_with?("+page.")) &&
         filename.includes?("/routes/")
        return true
      end

      false
    end

    def set_name
      @name = "js_sveltekit"
    end
  end
end
