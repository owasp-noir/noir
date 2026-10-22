require "../../../models/detector"

module Detector::Python
  class Bottle < Detector
    detector_for "python_bottle", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      # Necessary condition for every pattern below, which all spell
      # `bottle` literally: a memchr scan is far cheaper than the anchored
      # import regexes, and a file without the word cannot match them.
      return false unless file_contents.includes?("bottle")

      # Match `from bottle import ...` or `import bottle`.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+bottle\s+import\s+/)
      has_import = file_contents.match(/(^|\n)\s*import\s+bottle(\s|,|$)/)

      !!(has_from_import || has_import)
    end
  end
end
