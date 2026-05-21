require "../../../models/detector"

module Detector::Go
  class Huma < Detector
    # Huma v2 ships under `github.com/danielgtaylor/huma/v2`. A
    # go.mod require line is the strongest signal; individual
    # .go files import the package directly so we also catch
    # standalone scans where go.mod isn't in the base path.
    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("go.mod") && file_contents.includes?("github.com/danielgtaylor/huma")
        true
      elsif filename.ends_with?(".go") && file_contents.includes?("github.com/danielgtaylor/huma")
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.includes?("go.mod") || filename.ends_with?(".go")
    end

    def set_name
      @name = "go_huma"
    end
  end
end
