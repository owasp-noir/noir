require "../../../models/detector"

module Detector::Javascript
  class Koa < Detector
    detector_for "js_koa", extensions: %w[.js .mjs .cjs .jsx .ts .tsx], basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan instead of six.
    SIGNAL = Regex.union(
      /require\(['"]koa['"]\)/,
      /import Koa from ['"]koa['"]/,
      /import Router from ['"]koa-router['"]/,
      /require\(['"]koa-router['"]\)/,
      /require\(['"]koa-[a-zA-Z0-9-]+['"]\)/,
      /new Koa\(\)/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts")
      # Necessary condition for every marker below, which all spell `koa` or
      # `Koa` literally; a memchr scan is far cheaper than the alternation
      # regex.
      return false unless file_contents.includes?("koa") || file_contents.includes?("Koa")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
