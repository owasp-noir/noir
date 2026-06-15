require "../../../models/detector"

module Detector::Typescript
  class Nestjs < Detector
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
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx")
      file_contents.matches?(SIGNAL)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ts") || filename.ends_with?(".tsx") || filename.ends_with?(".cts") || filename.ends_with?(".mts") || filename.ends_with?(".js") || filename.ends_with?(".jsx") || filename.ends_with?(".cjs") || filename.ends_with?(".mjs") || File.basename(filename) == "package.json" || File.basename(filename) == "tsconfig.json"
    end

    def set_name
      @name = "ts_nestjs"
    end
  end
end
