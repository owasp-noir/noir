require "../../../models/detector"

module Detector::Python
  class Flask < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match framework imports while avoiding flask_* packages
      has_from_import = file_contents.match(/(^|\n)\s*from\s+flask\s+import\s+/)
      has_import = file_contents.match(/(^|\n)\s*import\s+flask(\s|,|$)/)

      !!(has_from_import || has_import)
    end

    def set_name
      @name = "python_flask"
    end
  end
end
