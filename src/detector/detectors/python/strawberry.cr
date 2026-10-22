require "../../../models/detector"

module Detector::Python
  class Strawberry < Detector
    detector_for "python_strawberry", extensions: %w[.py]

    # `strawberry` itself or the `strawberry_django` integration.
    IMPORT_RE = /^\s*(?:from\s+strawberry(?:_django)?(?:\.[\w.]+)?\s+import\b|import\s+strawberry(?:_django)?\b)/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      return false unless file_contents.includes?("strawberry")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
