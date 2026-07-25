require "../../../models/detector"

module Detector::Python
  class Quart < Detector
    detector_for "python_quart", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Accept any `from quart import ...` or `import quart` shape.
      # `quart_*` packages (e.g. `quart_cors`) are deliberately allowed
      # too — a project that imports a Quart extension is, in practice,
      # always a Quart project, and gating on the bare module would
      # miss apps that re-export `app` from a helper module.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+quart(\.[A-Za-z_][A-Za-z0-9_]*)?\s+import\s+/)
      has_import = file_contents.match(/(^|\n)\s*import\s+quart(\s|,|$)/)

      !!(has_from_import || has_import)
    end
  end
end
