require "../../../models/detector"

module Detector::CSharp
  class Carter < Detector
    detector_for "cs_carter", extensions: %w[.cs .csproj .props .targets]

    # Detects Carter (https://github.com/CarterCommunity/Carter), a
    # module library for ASP.NET Core minimal APIs. Carter projects
    # are also ASP.NET Core projects, so the surrounding
    # `cs_aspnet_core_mvc` detector fires too — Carter narrows the
    # surface to `ICarterModule.AddRoutes` blocks tagged as
    # `cs_carter`, and the analyzer skips files the MVC analyzer
    # already owns.
    CARTER_MODULE = /\bI?CarterModule\b/

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".csproj") || filename.ends_with?(".props") || filename.ends_with?(".targets")
        return true if file_contents.includes?("Include=\"Carter\"") ||
                       file_contents.includes?("Include='Carter'") ||
                       file_contents.includes?("\"Carter.")
      end

      return false unless filename.ends_with?(".cs")
      # `CarterModule` is Carter's abstract base class (base path + filters);
      # `ICarterModule` the bare interface. Both declare a Carter module, and
      # a module deriving from the base never has to name the interface.
      file_contents.includes?("using Carter") || content_matches?(file_contents, CARTER_MODULE)
    end
  end
end
