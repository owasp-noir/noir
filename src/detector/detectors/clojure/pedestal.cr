require "../../../models/detector"

module Detector::Clojure
  class Pedestal < Detector
    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}
    PROJECT_FILES      = {"project.clj", "deps.edn"}

    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      if PROJECT_FILES.includes?(basename)
        return true if file_contents.includes?("io.pedestal/pedestal")
        return true if file_contents.includes?("pedestal.service")
        return true if file_contents.includes?("pedestal.route")
        return true if file_contents.includes?("pedestal.jetty")
        return true if file_contents.includes?("pedestal.http-kit")
        return false
      end

      if CLOJURE_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
        return true if file_contents.includes?("io.pedestal.http")
        return true if file_contents.includes?("io.pedestal.connector")
        return true if file_contents.includes?("io.pedestal.route")
        return true if file_contents.includes?("io.pedestal.service")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".clj") || filename.ends_with?(".cljs") || filename.ends_with?(".cljc") || filename.ends_with?(".edn") || File.basename(filename) == "project.clj" || File.basename(filename) == "deps.edn"
    end

    def set_name
      @name = "clojure_pedestal"
    end
  end
end
