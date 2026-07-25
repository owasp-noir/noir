require "../../../models/detector"

module Detector::Python
  class Aiohttp < Detector
    detector_for "python_aiohttp", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      has_from_import = file_contents.match(/(^|\n)\s*from\s+aiohttp(\.|[\s])/)
      has_import = file_contents.match(/(^|\n)\s*import\s+aiohttp(\s|,|$|\.)/)

      !!(has_from_import || has_import)
    end
  end
end
