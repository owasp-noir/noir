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

    SOURCE_EXTENSIONS = %w[.js .mjs .cjs .jsx]

    def detect(filename : String, file_contents : String) : Bool
      return false unless SOURCE_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
      content_matches?(file_contents, SIGNAL)
    end
  end
end
