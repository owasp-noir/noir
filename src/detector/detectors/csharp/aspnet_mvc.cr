require "../../../models/detector"
require "../../../models/locator_keys"

module Detector::CSharp
  class AspNetMvc < Detector
    # `check_routeconfig` records every `RouteConfig.cs` path it
    # sees into `CodeLocator` for the analyzer to consume. Skipping
    # this detector after its first match would lose the
    # registration on subsequent files.
    detector_for "cs_aspnet_mvc",
      extensions: %w[.cs .csproj .config],
      idempotent: false

    CONTROLLER_INHERITANCE      = /:\s*Controller\b/
    CONTROLLER_BASE_INHERITANCE = /:\s*ControllerBase\b/

    def detect(filename : String, file_contents : String) : Bool
      check_routeconfig filename, file_contents

      if filename.includes?("packages.config")
        return true if file_contents.includes?("Microsoft.AspNet.Mvc")
      end

      if filename.ends_with?(".csproj")
        return true if file_contents.includes?("Microsoft.AspNet.Mvc") ||
                       file_contents.includes?("<Reference Include=\"System.Web.Mvc")
      end

      if filename.ends_with?(".cs")
        return false if content_matches?(file_contents, CONTROLLER_BASE_INHERITANCE)

        has_namespace = file_contents.includes?("using System.Web.Mvc;")
        has_controller_signal = content_matches?(file_contents, CONTROLLER_INHERITANCE) ||
                                file_contents.includes?("ActionResult") ||
                                file_contents.includes?("routes.MapRoute") ||
                                file_contents.includes?(".MapRoute")
        return true if has_namespace && has_controller_signal
      end

      false
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
