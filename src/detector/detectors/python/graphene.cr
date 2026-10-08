require "../../../models/detector"

module Detector::Python
  class Graphene < Detector
    detector_for "python_graphene", extensions: %w[.py]

    # `graphene` and its integrations (`graphene_django`,
    # `graphene_sqlalchemy`, `graphene_mongo`, ...).
    IMPORT_RE = /^\s*(?:from\s+graphene(?:_\w+)?(?:\.[\w.]+)?\s+import\b|import\s+graphene(?:_\w+)?\b)/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      return false unless file_contents.includes?("graphene")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
