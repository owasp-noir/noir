require "../../../models/detector"

module Detector::Javascript
  class Nestjs < Detector
    detector_for "js_nestjs",
      extensions: %w[.js .mjs .cjs .jsx]

    # Single precompiled alternation — one PCRE2 scan instead of seven.
    SIGNAL = Regex.union(
      /require\(['"]@nestjs\/core['"]\)/,
      /require\(['"]@nestjs\/common['"]\)/,
      /import.*from ['"]@nestjs\/core['"]/,
      /import.*from ['"]@nestjs\/common['"]/,
      /@Controller\s*\(/,
      /@Module\s*\(/,
      /NestFactory\.create\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") || filename.ends_with?(".jsx")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
