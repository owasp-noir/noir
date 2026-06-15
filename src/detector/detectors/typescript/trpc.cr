require "../../../models/detector"

module Detector::Typescript
  class TRPC < Detector
    # Single precompiled alternation — one PCRE2 scan instead of eight.
    SIGNAL = Regex.union(
      /import[^'"`]+from\s+['"`]@trpc\/server(?:\/[^'"`]*)?['"`]/,
      /require\(\s*['"`]@trpc\/server(?:\/[^'"`]*)?['"`]\s*\)/,
      /import[^'"`]+from\s+['"`]@trpc\/next['"`]/,
      /initTRPC\b/,
      /createTRPCRouter\s*\(/,
      /fetchRequestHandler\s*\(/,
      /createNextApiHandler\s*\(/,
      /trpcExpress\.createExpressMiddleware\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
                          filename.ends_with?(".cts") || filename.ends_with?(".mts") ||
                          filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
                          filename.ends_with?(".cjs") || filename.ends_with?(".mjs") ||
                          File.basename(filename) == "package.json"

      if File.basename(filename) == "package.json"
        return file_contents.includes?("\"@trpc/server\"") || file_contents.includes?("\"@trpc/next\"")
      end

      if file_contents.matches?(SIGNAL)
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
        filename.ends_with?(".cts") || filename.ends_with?(".mts") ||
        filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
        filename.ends_with?(".cjs") || filename.ends_with?(".mjs") ||
        File.basename(filename) == "package.json"
    end

    def set_name
      @name = "ts_trpc"
    end
  end
end
