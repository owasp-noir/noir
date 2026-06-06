require "../../../models/detector"

module Detector::Python
  class Flask < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match framework imports while avoiding unrelated flask_* packages.
      # Flask-AppBuilder is a Flask extension whose projects often expose
      # routes with `@expose` and never import `flask` directly in view files.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+flask\s+import\s+/)
      has_import = file_contents.match(/(^|\n)\s*import\s+flask(\s|,|$)/)
      has_appbuilder_import = file_contents.match(/(^|\n)\s*(?:from|import)\s+flask_appbuilder\b/)

      !!(has_from_import || has_import || has_appbuilder_import)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".py")
    end

    def set_name
      @name = "python_flask"
    end
  end
end
