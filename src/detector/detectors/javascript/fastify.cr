require "../../../models/detector"

module Detector::Javascript
  class Fastify < Detector
    detector_for "js_fastify",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan instead of five.
    SIGNAL = Regex.union(
      /require\(['"]fastify['"]\)/,
      /from ['"]fastify['"]/,
      /fastify\s*\(\s*\{/,
      /fastify\.register\s*\(/,
      /fastify\.(get|post|put|delete|patch|head|options|query|route)\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") ||
                          filename.ends_with?(".jsx") || filename.ends_with?(".tsx") || filename.ends_with?(".cjs")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
