require "../../../models/detector"

module Detector::Clojure
  class Pedestal < Detector
    detector_for "clojure_pedestal",
      extensions: %w[.clj .cljs .cljc .edn],
      basenames: %w[project.clj deps.edn]

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
  end
end
