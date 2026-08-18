require "../../../models/detector"

module Detector::Typescript
  class Nestjs < Detector
    detector_for "ts_nestjs",
      extensions: %w[.ts .tsx .cts .mts]

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
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
                          filename.ends_with?(".cts") || filename.ends_with?(".mts")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
