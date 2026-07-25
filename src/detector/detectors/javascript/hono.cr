require "../../../models/detector"

module Detector::Javascript
  class Hono < Detector
    detector_for "js_hono", extensions: %w[.js .mjs .cjs .jsx .ts .tsx], basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan instead of three.
    SIGNAL = Regex.union(
      /require\(['"]hono['"]\)/,
      /from ['"]hono['"]/,
      /new\s+Hono\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      [".js", ".mjs", ".ts", ".jsx", ".tsx", ".cjs"].any? { |ext| filename.ends_with?(ext) } &&
        content_matches?(file_contents, SIGNAL)
    end
  end
end
