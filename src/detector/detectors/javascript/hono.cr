require "../../../models/detector"

module Detector::Javascript
  class Hono < Detector
    def detect(filename : String, file_contents : String) : Bool
      [".js", ".mjs", ".ts", ".jsx", ".tsx", ".cjs"].any? { |ext| filename.ends_with?(ext) } &&
        !!(file_contents.match(/require\(['"]hono['"]\)/) ||
          file_contents.match(/from ['"]hono['"]/) ||
          file_contents.match(/new\s+Hono\s*\(/))
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_hono"
    end
  end
end
