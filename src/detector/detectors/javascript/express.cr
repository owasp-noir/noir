require "../../../models/detector"

module Detector::Javascript
  class Express < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") || filename.ends_with?(".cjs")) &&
         (file_contents.match(/require\(['"]express['"]\)/) ||
         file_contents.match(/from ['"]express['"]/) ||
         file_contents.match(/app\.use\(express\.json\(\)\)/) ||
         file_contents.match(/app\.use\(express\.urlencoded\(\{ extended: true \}\)\)/))
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_express"
    end
  end
end
