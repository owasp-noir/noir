require "../../../models/detector"

module Detector::Clojure
  # Detects Clojure command-line apps via clojure.tools.cli, cli-matic,
  # babashka.cli, or *command-line-args*. Never gates on bare
  # (System/getenv) or bare environ.core (Ring/worker config reads both) —
  # environ.core is a generic 12-factor config library used just as much by
  # web apps and services, so it only annotates params on a `cli://`
  # endpoint one of the markers below already established.
  class Cli < Detector
    detector_for "clojure_cli", extensions: %w[.clj .cljs .cljc]

    MARKERS = /clojure\.tools\.cli\b|\(\s*(?:[\w.-]+\/)?parse-opts\b|\bcli-matic\b|\*command-line-args\*|\bbabashka\.cli\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      content_matches?(file_contents, MARKERS)
    end
  end
end
