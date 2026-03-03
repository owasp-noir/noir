require "../../../models/detector"

module Detector::Python
  class Django < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match framework imports while avoiding django_* packages
      has_from_import = file_contents.match(/(^|\n)\s*from\s+django\./)
      has_import = file_contents.match(/(^|\n)\s*import\s+django(\s|,|$)/)

      !!(has_from_import || has_import)
    end

    def set_name
      @name = "python_django"
    end
  end
end
