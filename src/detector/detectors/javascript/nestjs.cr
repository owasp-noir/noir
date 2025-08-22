require "../../../models/detector"

module Detector::Javascript
  class Nestjs < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".js") || filename.ends_with?(".ts") || filename.ends_with?(".jsx") || filename.ends_with?(".tsx")) &&
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

    def set_name
      @name = "js_nestjs"
    end
  end
end
