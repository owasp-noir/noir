require "../../../models/detector"

module Detector::Javascript
  class Koa < Detector
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
      file_contents.matches?(SIGNAL)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_koa"
    end
  end
end
