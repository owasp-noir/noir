require "../../../models/detector"

module Detector::Python
  class Bottle < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match `from bottle import ...` or `import bottle`.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+bottle\s+import\s+/)
      has_import = file_contents.match(/(^|\n)\s*import\s+bottle(\s|,|$)/)

      !!(has_from_import || has_import)
    end

    def set_name
      @name = "python_bottle"
    end
  end
end
