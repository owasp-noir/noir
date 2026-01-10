require "../../../models/detector"

module Detector::Typescript
  class TanstackRouter < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".ts") || filename.ends_with?(".tsx")) &&
         (file_contents.match(/import.*from ['"]@tanstack\/react-router['"]/) ||
         file_contents.match(/import.*from ['"]@tanstack\/router['"]/) ||
         file_contents.match(/require\(['"]@tanstack\/react-router['"]\)/) ||
         file_contents.match(/require\(['"]@tanstack\/router['"]\)/) ||
         file_contents.match(/createFileRoute\s*\(/) ||
         file_contents.match(/createRootRoute\s*\(/) ||
         file_contents.match(/createRoute\s*\(/) ||
         file_contents.match(/createRouter\s*\(/))
        true
      else
        false
      end
    end

    def set_name
      @name = "ts_tanstack_router"
    end
  end
end
