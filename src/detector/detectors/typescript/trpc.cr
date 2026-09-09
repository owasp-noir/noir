require "../../../models/detector"

module Detector::Typescript
  class TRPC < Detector
    detector_for "ts_trpc",
      extensions: %w[.ts .tsx .cts .mts .js .jsx .cjs .mjs],
      basenames: %w[package.json]

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

      # Necessary condition for every marker below, which all spell `trpc` or
      # `TRPC` or `fetchRequestHandler` or `createNextApiHandler` literally; a
      # memchr scan is far cheaper than the alternation regex.
      return false unless file_contents.includes?("trpc") || file_contents.includes?("TRPC") || file_contents.includes?("fetchRequestHandler") || file_contents.includes?("createNextApiHandler")
      if content_matches?(file_contents, SIGNAL)
        return true
      end

      false
    end
  end
end
