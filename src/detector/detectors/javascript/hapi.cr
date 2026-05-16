require "../../../models/detector"

module Detector::Javascript
  class Hapi < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") ||
                          filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") ||
                          filename.ends_with?(".ts")
      file_contents.includes?("@hapi/hapi") ||
        file_contents.includes?("require('hapi')") ||
        file_contents.includes?("require(\"hapi\")") ||
        file_contents.includes?("from 'hapi'") ||
        file_contents.includes?("from \"hapi\"")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_hapi"
    end
  end
end
