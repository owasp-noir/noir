require "../../../models/detector"

module Detector::CSharp
  class Carter < Detector
    # Detects Carter (https://github.com/CarterCommunity/Carter), a
    # module library for ASP.NET Core minimal APIs. Carter projects
    # are also ASP.NET Core projects, so the surrounding
    # `cs_aspnet_core_mvc` detector fires too — Carter narrows the
    # surface to `ICarterModule.AddRoutes` blocks tagged as
    # `cs_carter`, and the analyzer skips files the MVC analyzer
    # already owns.
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".csproj") || filename.ends_with?(".props") || filename.ends_with?(".targets")
        return true if file_contents.includes?("Include=\"Carter\"") ||
                       file_contents.includes?("Include='Carter'") ||
                       file_contents.includes?("\"Carter.")
      end

      return false unless filename.ends_with?(".cs")
      file_contents.includes?("using Carter") || file_contents.includes?("ICarterModule")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cs") || filename.ends_with?(".csproj") ||
        filename.ends_with?(".props") || filename.ends_with?(".targets")
    end

    def set_name
      @name = "cs_carter"
    end
  end
end
