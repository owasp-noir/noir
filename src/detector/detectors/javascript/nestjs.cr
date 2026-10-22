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
      # Necessary condition for every marker below, which all spell `@nestjs`
      # or `@Controller` or `@Module` or `NestFactory` literally; a memchr
      # scan is far cheaper than the alternation regex.
      return false unless file_contents.includes?("@nestjs") || file_contents.includes?("@Controller") || file_contents.includes?("@Module") || file_contents.includes?("NestFactory")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
