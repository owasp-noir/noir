require "../../../models/detector"

module Detector::Python
  class Aiohttp < Detector
    detector_for "python_aiohttp", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      # Necessary condition for every pattern below, which all spell
      # `aiohttp` literally: a memchr scan is far cheaper than the anchored
      # import regexes, and a file without the word cannot match them.
      return false unless file_contents.includes?("aiohttp")

      has_from_import = file_contents.match(/(^|\n)\s*from\s+aiohttp(\.|[\s])/)
      has_import = file_contents.match(/(^|\n)\s*import\s+aiohttp(\s|,|$|\.)/)

      !!(has_from_import || has_import)
    end
  end
end
