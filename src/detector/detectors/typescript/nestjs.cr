require "../../../models/detector"

module Detector::Typescript
  class Nestjs < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".ts") || filename.ends_with?(".tsx")) &&
         (file_contents.match(/require\(['"]@nestjs\/core['"]\)/) ||
         file_contents.match(/require\(['"]@nestjs\/common['"]\)/) ||
         file_contents.match(/import.*from ['"]@nestjs\/core['"]/) ||
         file_contents.match(/import.*from ['"]@nestjs\/common['"]/) ||
         file_contents.match(/@Controller\s*\(/) ||
         file_contents.match(/@Module\s*\(/) ||
         file_contents.match(/NestFactory\.create\s*\(/))
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ts") || filename.ends_with?(".tsx") || filename.ends_with?(".cts") || filename.ends_with?(".mts") || filename.ends_with?(".js") || filename.ends_with?(".jsx") || filename.ends_with?(".cjs") || filename.ends_with?(".mjs") || File.basename(filename) == "package.json" || File.basename(filename) == "tsconfig.json"
    end

    def set_name
      @name = "ts_nestjs"
    end
  end
end
