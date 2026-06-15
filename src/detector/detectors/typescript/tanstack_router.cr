require "../../../models/detector"

module Detector::Typescript
  class TanstackRouter < Detector
    # Single precompiled alternation — one PCRE2 scan instead of eight.
    SIGNAL = Regex.union(
      /import.*from ['"]@tanstack\/react-router['"]/,
      /import.*from ['"]@tanstack\/router['"]/,
      /require\(['"]@tanstack\/react-router['"]\)/,
      /require\(['"]@tanstack\/router['"]\)/,
      /createFileRoute\s*\(/,
      /createRootRoute\s*\(/,
      /createRoute\s*\(/,
      /createRouter\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx")
      file_contents.matches?(SIGNAL)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ts") || filename.ends_with?(".tsx") || filename.ends_with?(".cts") || filename.ends_with?(".mts") || filename.ends_with?(".js") || filename.ends_with?(".jsx") || filename.ends_with?(".cjs") || filename.ends_with?(".mjs") || File.basename(filename) == "package.json" || File.basename(filename) == "tsconfig.json"
    end

    def set_name
      @name = "ts_tanstack_router"
    end
  end
end
