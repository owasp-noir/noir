require "../../../models/detector"

module Detector::Python
  class Masonite < Detector
    detector_for "python_masonite", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      # Necessary condition for every pattern below, which all spell
      # `masonite` literally: a memchr scan is far cheaper than the anchored
      # import regexes, and a file without the word cannot match them.
      return false unless file_contents.includes?("masonite")

      # Match framework imports (`masonite.routes`, `masonite.controllers`,
      # `masonite.views`, plain `import masonite`, ...) while avoiding
      # unrelated `masonite_*` packages.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+masonite(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+masonite(\s|,|\.|$)/)

      !!(has_from_import || has_import)
    end
  end
end
