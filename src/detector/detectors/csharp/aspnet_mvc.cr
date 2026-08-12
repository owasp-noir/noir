require "../../../models/detector"

module Detector::CSharp
  class AspNetMvc < Detector
    # `check_routeconfig` records every `RouteConfig.cs` path it
    # sees into `CodeLocator` for the analyzer to consume. Skipping
    # this detector after its first match would lose the
    # registration on subsequent files.
    detector_for "cs_aspnet_mvc",
      extensions: %w[.cs .csproj .vbproj .sln .config],
      idempotent: false

    def detect(filename : String, file_contents : String) : Bool
      check_routeconfig filename, file_contents

      return false unless filename.includes?("packages.config")
      file_contents.includes?("Microsoft.AspNet.Mvc")
    end

    def check_routeconfig(filename : String, file_contents : String)
      return unless filename.includes?("RouteConfig.cs")

      if file_contents.includes?(".MapRoute")
        locator = CodeLocator.instance
        locator.set(Noir::LocatorKeys::CS_APINET_MVC_ROUTECONFIG, filename)
      end
    end
  end
end
