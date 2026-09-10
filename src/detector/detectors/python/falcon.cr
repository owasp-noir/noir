require "../../../models/detector"

module Detector::Python
  class Falcon < Detector
    detector_for "python_falcon", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      # Necessary condition for every pattern below, which all spell
      # `falcon` literally: a memchr scan is far cheaper than the anchored
      # import regexes, and a file without the word cannot match them.
      return false unless file_contents.includes?("falcon")

      # Match `from falcon import ...` or `import falcon`. Avoid matching
      # unrelated packages such as `falconpy`.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+falcon(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+falcon(\s|,|$|\.)/)

      !!(has_from_import || has_import)
    end
  end
end
