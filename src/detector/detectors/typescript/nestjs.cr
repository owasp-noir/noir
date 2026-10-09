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

    FOREIGN_CONTROLLER_RE = /@midwayjs\/|(?:\bfrom|\brequire\s*\()\s*['"](?:routing-controllers['"]|@tsed\/)/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
                          filename.ends_with?(".cts") || filename.ends_with?(".mts")
      # Necessary condition for every marker below, which all spell `@nestjs`
      # or `@Controller` or `@Module` or `NestFactory` literally; a memchr
      # scan is far cheaper than the alternation regex.
      return false unless file_contents.includes?("@nestjs") || file_contents.includes?("@Controller") || file_contents.includes?("@Module") || file_contents.includes?("NestFactory")
      # Midway, routing-controllers and Ts.ED import the same `@Controller`
      # vocabulary from their own packages.
      return false if file_contents.matches?(FOREIGN_CONTROLLER_RE)
      content_matches?(file_contents, SIGNAL)
    end
  end
end
