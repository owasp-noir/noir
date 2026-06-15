require "../../../models/detector"

module Detector::Javascript
  class Fastify < Detector
    # Single precompiled alternation — one PCRE2 scan instead of five.
    SIGNAL = Regex.union(
      /require\(['"]fastify['"]\)/,
      /from ['"]fastify['"]/,
      /fastify\s*\(\s*\{/,
      /fastify\.register\s*\(/,
      /fastify\.(get|post|put|delete|patch|head|options)\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") ||
                          filename.ends_with?(".jsx") || filename.ends_with?(".tsx") || filename.ends_with?(".cjs")
      file_contents.matches?(SIGNAL)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_fastify"
    end
  end
end
