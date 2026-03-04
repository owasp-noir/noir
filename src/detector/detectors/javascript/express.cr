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

    def set_name
      @name = "js_express"
    end
  end
end
