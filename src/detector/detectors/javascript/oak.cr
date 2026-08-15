require "../../../models/detector"

module Detector::Javascript
  class Oak < Detector
    detector_for "js_oak",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json deno.json deno.jsonc import_map.json]

    MANIFEST_BASENAMES = %w[package.json deno.json deno.jsonc import_map.json]

    # Oak ships no package.json of its own — it's a Deno-native
    # framework — so the reliable signal is the import specifier
    # itself:
    #   * the JSR package, `import { Router } from "@oak/oak"`,
    #     including the bare `jsr:@oak/oak` specifier form.
    #   * the legacy URL import,
    #     `import { Router } from "https://deno.land/x/oak@v.../mod.ts"`
    #     (any version, any subpath — the bare "deno.land/x/oak"
    #     substring covers all of them).
    # Both forms are quoted strings rather than anchored to `from`/
    # `require(` so the same signal also fires inside a Deno import map
    # (`deno.json`/`deno.jsonc`/`import_map.json`), where the specifier
    # is a bare JSON key/value: `"imports": { "@oak/oak": "jsr:@oak/
    # oak@^17.1.0" }` or `"oak/": "https://deno.land/x/oak@v12.6.1/"`.
    SIGNAL = Regex.union(
      /["']@oak\/oak["']/,
      /["']jsr:@oak\/oak["']/,
      /["'](?:https?:\/\/)?deno\.land\/x\/oak(?:[@\/][^"']*)?["']/,
    )

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)
      return content_matches?(file_contents, SIGNAL) if MANIFEST_BASENAMES.includes?(base)

      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") || filename.ends_with?(".jsx") ||
                          filename.ends_with?(".ts") || filename.ends_with?(".tsx")

      content_matches?(file_contents, SIGNAL)
    end
  end
end
