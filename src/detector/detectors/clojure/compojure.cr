require "../../../models/detector"

module Detector::Clojure
  class Compojure < Detector
    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}
    PROJECT_FILES      = {"project.clj", "deps.edn"}

    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      if PROJECT_FILES.includes?(basename)
        return file_contents.includes?("compojure")
      end

      if CLOJURE_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
        return true if file_contents.includes?("compojure.core")
        return true if file_contents.includes?("defroutes") && file_contents.match(/\([A-Z]+?\s+"/)
      end

      false
    end

    def set_name
      @name = "clojure_compojure"
    end
  end
end
