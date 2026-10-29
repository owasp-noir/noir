require "../../../models/detector"

module Detector::Javascript
  class Hono < Detector
    detector_for "js_hono", extensions: %w[.js .mjs .cjs .jsx .ts .mts .cts .tsx], basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan instead of three.
    # `@hono/zod-openapi` re-exports Hono as `OpenAPIHono`; an app built on
    # it need never import `hono` itself.
    SIGNAL = Regex.union(
      /require\(['"]hono['"]\)/,
      /from ['"]hono['"]/,
      /new\s+Hono\s*\(/,
      /from ['"]@hono\/zod-openapi['"]/,
      /new\s+OpenAPIHono\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      [".js", ".mjs", ".ts", ".mts", ".cts", ".jsx", ".tsx", ".cjs"].any? { |ext| filename.ends_with?(ext) } &&
        (file_contents.includes?("hono") || file_contents.includes?("Hono")) &&
        content_matches?(file_contents, SIGNAL)
    end
  end
end
