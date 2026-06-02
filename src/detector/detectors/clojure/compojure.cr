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
        # compojure-api (`compojure.api.sweet`/`.core`/`.resource`) shares the
        # GET/POST/context macros and adds the `resource` DSL — files often
        # pull only this ns rather than `compojure.core`.
        return true if file_contents.includes?("compojure.api")
        return true if file_contents.includes?("defroutes") && file_contents.match(/\([A-Z]+?\s+"/)
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".clj") || filename.ends_with?(".cljs") || filename.ends_with?(".cljc") || filename.ends_with?(".edn") || File.basename(filename) == "project.clj" || File.basename(filename) == "deps.edn"
    end

    def set_name
      @name = "clojure_compojure"
    end
  end
end
