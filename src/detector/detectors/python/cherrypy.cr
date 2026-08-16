require "../../../models/detector"

module Detector::Python
  class CherryPy < Detector
    detector_for "python_cherrypy", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match `from cherrypy import ...` or `import cherrypy`. `cherrypy`
      # is a distinctive package name (unlike a generic pattern such as
      # "class with an index method"), so an import alone is a reliable
      # signal — same convention as the Bottle/Pyramid detectors.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+cherrypy(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+cherrypy(\s|,|\.|$)/)

      !!(has_from_import || has_import)
    end
  end
end
