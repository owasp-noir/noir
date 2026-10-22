require "../../../models/detector"

module Detector::Python
  class Chalice < Detector
    detector_for "python_chalice", extensions: %w[.py]

    IMPORT_RE = /^\s*(?:from\s+chalice(?:\.[\w.]+)?\s+import\b|import\s+chalice\b)/m

    # `from chalice import Chalice` (the app) or `Blueprint` (a
    # `chalicelib/` module) — any `chalice` import marks the project.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      return false unless file_contents.includes?("chalice")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
