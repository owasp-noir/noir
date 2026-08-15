require "../../../models/detector"

module Detector::Python
  class Masonite < Detector
    detector_for "python_masonite", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match framework imports (`masonite.routes`, `masonite.controllers`,
      # `masonite.views`, plain `import masonite`, ...) while avoiding
      # unrelated `masonite_*` packages.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+masonite(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+masonite(\s|,|\.|$)/)

      !!(has_from_import || has_import)
    end
  end
end
