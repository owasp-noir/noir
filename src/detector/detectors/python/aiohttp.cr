require "../../../models/detector"

module Detector::Python
  class Aiohttp < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      has_from_import = file_contents.match(/(^|\n)\s*from\s+aiohttp(\.|[\s])/)
      has_import = file_contents.match(/(^|\n)\s*import\s+aiohttp(\s|,|$|\.)/)

      !!(has_from_import || has_import)
    end

    def set_name
      @name = "python_aiohttp"
    end
  end
end
