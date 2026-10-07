require "../../../models/detector"

module Detector::CSharp
  class Razor < Detector
    detector_for "cs_razor", extensions: %w[.cshtml .razor]

    # An `@page` directive or a Blazor `@attribute [Route]` at the start of a
    # line; a CSS `@page` rule inside Razor markup is written `@@page`.
    PAGE_DIRECTIVE = /^[ \t]*@(?:page\b|attribute\s+\[Route\()/m

    def detect(filename : String, file_contents : String) : Bool
      file_contents.matches?(PAGE_DIRECTIVE)
    end
  end
end
