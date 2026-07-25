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
      content_matches?(file_contents, SIGNAL)
    end
  end
end
