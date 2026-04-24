require "../../../models/detector"

module Detector::Python
  class Pyramid < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      has_from_import = file_contents.match(/(^|\n)\s*from\s+pyramid(\.|\s+import\s+)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+pyramid(\s|,|\.|$)/)

      !!(has_from_import || has_import)
    end

    def set_name
      @name = "python_pyramid"
    end
  end
end
