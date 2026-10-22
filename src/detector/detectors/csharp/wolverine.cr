require "../../../models/detector"

module Detector::CSharp
  class Wolverine < Detector
    detector_for "cs_wolverine", extensions: %w[.cs .csproj]

    def detect(filename : String, file_contents : String) : Bool
      if Noir::FileExtension.fold(filename).ends_with?(".csproj")
        file_contents.includes?("WolverineFx.Http")
      else
        file_contents.includes?("using Wolverine.Http;") || file_contents.includes?("MapWolverineEndpoints(")
      end
    end
  end
end
