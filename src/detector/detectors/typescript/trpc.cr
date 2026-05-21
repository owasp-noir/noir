require "../../../models/detector"

module Detector::Typescript
  class TRPC < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
                          filename.ends_with?(".cts") || filename.ends_with?(".mts") ||
                          filename.ends_with?(".js") || filename.ends_with?(".jsx") ||
                          filename.ends_with?(".cjs") || filename.ends_with?(".mjs") ||
                          File.basename(filename) == "package.json"

      if File.basename(filename) == "package.json"
        return file_contents.includes?("\"@trpc/server\"") || file_contents.includes?("\"@trpc/next\"")
      end

      if file_contents.match(/import[^'"`]+from\s+['"`]@trpc\/server(?:\/[^'"`]*)?['"`]/) ||
         file_contents.match(/require\(\s*['"`]@trpc\/server(?:\/[^'"`]*)?['"`]\s*\)/) ||
         file_contents.match(/import[^'"`]+from\s+['"`]@trpc\/next['"`]/) ||
         file_contents.match(/initTRPC\b/) ||
         file_contents.match(/createTRPCRouter\s*\(/) ||
         file_contents.match(/fetchRequestHandler\s*\(/) ||
         file_contents.match(/createNextApiHandler\s*\(/) ||
         file_contents.match(/trpcExpress\.createExpressMiddleware\s*\(/)
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
