require "../../../models/detector"

module Detector::Clojure
  # Detects Clojure command-line apps via clojure.tools.cli, cli-matic,
  # babashka.cli, or *command-line-args*. Never gates on bare
  # (System/getenv) or bare environ.core (Ring/worker config reads both) —
  # environ.core is a generic 12-factor config library used just as much by
  # web apps and services, so it only annotates params on a `cli://`
  # endpoint one of the markers below already established.
  class Cli < Detector
    MARKERS = /clojure\.tools\.cli\b|\(\s*(?:[\w.-]+\/)?parse-opts\b|\bcli-matic\b|\*command-line-args\*|\bbabashka\.cli\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".clj") || filename.ends_with?(".cljs") || filename.ends_with?(".cljc")
    end

    def set_name
      @name = "clojure_cli"
    end
  end
end
