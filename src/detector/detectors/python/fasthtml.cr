require "../../../models/detector"

module Detector::Python
  class FastHTML < Detector
    detector_for "python_fasthtml", extensions: %w[.py]

    IMPORT_RE = /^\s*(?:from\s+fasthtml(?:\.[\w.]+)?\s+import\b|import\s+fasthtml\b)/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py") && file_contents.includes?("fasthtml")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
