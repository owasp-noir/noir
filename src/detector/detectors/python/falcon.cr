require "../../../models/detector"

module Detector::Python
  class Falcon < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match `from falcon import ...` or `import falcon`. Avoid matching
      # unrelated packages such as `falconpy`.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+falcon(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+falcon(\s|,|$|\.)/)

      !!(has_from_import || has_import)
    end

    def set_name
      @name = "python_falcon"
    end
  end
end
