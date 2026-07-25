require "../../../models/detector"

module Detector::Go
  class Huma < Detector
    # Huma v2 ships under `github.com/danielgtaylor/huma/v2`. A
    # go.mod require line is the strongest signal; individual
    # .go files import the package directly so we also catch
    # standalone scans where go.mod isn't in the base path.
    IMPORT_PATTERN = Regex.union("github.com/danielgtaylor/huma")

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("go.mod") || filename.ends_with?(".go")

      content_matches?(file_contents, IMPORT_PATTERN)
    end

    def applicable?(filename : String) : Bool
      filename.includes?("go.mod") || filename.ends_with?(".go")
    end

    def set_name
      @name = "go_huma"
    end
  end
end
