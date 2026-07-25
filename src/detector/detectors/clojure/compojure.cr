require "../../../models/detector"

module Detector::Clojure
  class Compojure < Detector
    detector_for "clojure_compojure",
      extensions: %w[.clj .cljs .cljc .edn],
      basenames: %w[project.clj deps.edn]

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
  end
end
