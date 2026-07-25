require "../../../models/detector"

module Detector::Clojure
  class Ring < Detector
    detector_for "clojure_ring",
      extensions: %w[.clj .cljs .cljc .edn],
      basenames: %w[project.clj deps.edn]

    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}
    PROJECT_FILES      = {"project.clj", "deps.edn"}

    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      if PROJECT_FILES.includes?(basename)
        # When the project also pulls a router built on top of Ring
        # (Compojure, Reitit), attribute the framework to that router rather
        # than its transitive Ring dependency — the Ring analyzer still
        # fires on individual files that use the raw request map directly.
        return false if file_contents.includes?("compojure")
        return false if file_contents.includes?("metosin/reitit")
        return false if file_contents.includes?("reitit/reitit")

        return true if file_contents.includes?("ring/ring-core")
        return true if file_contents.includes?("ring/ring-jetty-adapter")
        return true if file_contents.includes?("ring/ring-servlet")
        return true if file_contents.includes?("ring/ring-devel")
        return false
      end

      if CLOJURE_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
        return true if file_contents.includes?("ring.adapter")
        return true if file_contents.includes?("ring.core.protocols")
        return true if file_contents.includes?("ring.middleware")
        # Direct Ring dispatch handler signature — `(:request-method req)` /
        # `(:uri req)` is the canonical Ring request-map access pattern.
        return true if file_contents.includes?(":request-method") && file_contents.includes?(":uri")
      end

      false
    end
  end
end
