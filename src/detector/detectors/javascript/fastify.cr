require "../../../models/detector"

module Detector::Javascript
  class Fastify < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") ||
         filename.ends_with?(".jsx") || filename.ends_with?(".tsx")) &&
         (file_contents.match(/require\(['"]fastify['"]\)/) ||
         file_contents.match(/import fastify from ['"]fastify['"]/) ||
         file_contents.match(/import \{ fastify \} from ['"]fastify['"]/) ||
         file_contents.match(/fastify\s*\(\s*\{/) ||
         file_contents.match(/fastify\.register\s*\(/) ||
         file_contents.match(/fastify\.(get|post|put|delete|patch|head|options)\s*\(/))
        true
      else
        false
      end
    end

    def set_name
      @name = "js_fastify"
    end
  end
end
