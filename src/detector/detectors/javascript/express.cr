require "../../../models/detector"

module Detector::Javascript
  class Express < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.includes?(".js") || filename.includes?(".mjs") || filename.includes?(".ts")) &&
         (file_contents.match(/require\(['"]express['"]\)/) ||
         file_contents.match(/import express from ['"]express['"]/) ||
         file_contents.match(/require\(['"]express['"]\)/) ||
         file_contents.match(/import { Router } from ['"]express['"]/))
        true
      else
        false
      end
    end

    def set_name
      @name = "js_express"
    end
  end
end
