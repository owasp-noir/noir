require "../../../models/detector"

module Detector::Javascript
  class Hapi < Detector
    MARKERS = Regex.union(
      "@hapi/hapi",
      "require('hapi')", "require(\"hapi\")",
      "from 'hapi'", "from \"hapi\"",
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") ||
                          filename.ends_with?(".mjs") ||
                          filename.ends_with?(".cjs") ||
                          filename.ends_with?(".ts")
      content_matches?(file_contents, MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_hapi"
    end
  end
end
