require "../../../models/detector"

module Detector::Clojure
  class Reitit < Detector
    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}
    PROJECT_FILES      = {"project.clj", "deps.edn"}

    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      if PROJECT_FILES.includes?(basename)
        return true if file_contents.includes?("metosin/reitit")
        return true if file_contents.includes?("reitit/reitit")
        return true if file_contents.includes?("reitit.core") || file_contents.includes?("reitit.ring") || file_contents.includes?("reitit.http")
        return false
      end

      if CLOJURE_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
        # Any `reitit.*` namespace import marks a reitit file — routes are
        # frequently defined in namespaces that only pull a coercion or
        # middleware ns rather than the core/ring/http entry points.
        return true if file_contents.includes?("reitit.")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".clj") || filename.ends_with?(".cljs") || filename.ends_with?(".cljc") || filename.ends_with?(".edn") || File.basename(filename) == "project.clj" || File.basename(filename) == "deps.edn"
    end

    def set_name
      @name = "clojure_reitit"
    end
  end
end
