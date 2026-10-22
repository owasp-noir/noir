require "../../../models/detector"

module Detector::Python
  class Frappe < Detector
    detector_for "python_frappe", extensions: %w[.py]

    IMPORT_RE = /^\s*(?:from\s+frappe(?:\.[\w.]+)?\s+import\b|import\s+frappe\b)/m

    # Any `frappe` import: Frappe apps (ERPNext, HRMS, ...) and the
    # framework itself import it in every controller and API module.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      return false unless file_contents.includes?("frappe")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
