require "../../../models/detector"

module Detector::Python
  class Pyramid < Detector
    detector_for "python_pyramid", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      has_from_import = file_contents.match(/(^|\n)\s*from\s+pyramid(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+pyramid(\s|,|\.|$)/)

      !!(has_from_import || has_import)
    end
  end
end
