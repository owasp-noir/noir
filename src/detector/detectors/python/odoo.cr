require "../../../models/detector"

module Detector::Python
  class Odoo < Detector
    detector_for "python_odoo", extensions: %w[.py]

    IMPORT_RE = /^\s*(?:from\s+(?:odoo|openerp)(?:\.[\w.]+)?\s+import\b|import\s+(?:odoo|openerp)\b)/m

    # Any `odoo` (or pre-10 `openerp`) import: controllers, models and
    # `odoo.addons.*` cross-module imports all mark an Odoo addon tree.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      return false unless file_contents.includes?("odoo") || file_contents.includes?("openerp")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
