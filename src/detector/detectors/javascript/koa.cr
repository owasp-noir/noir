require "../../../models/detector"

module Detector::Javascript
  class Koa < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts")) &&
         (file_contents.match(/require\(['"]koa['"]\)/) ||
         file_contents.match(/import Koa from ['"]koa['"]/) ||
         file_contents.match(/import Router from ['"]koa-router['"]/) ||
         file_contents.match(/new Koa\(\)/) ||
         file_contents.match(/app\.use\(/))
        true
      else
        false
      end
    end

    def set_name
      @name = "js_koa"
    end
  end
end
