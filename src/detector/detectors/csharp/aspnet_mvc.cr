require "../../../models/detector"

module Detector::CSharp
  class AspNetMvc < Detector
    def detect(filename : String, file_contents : String) : Bool
      check_routeconfig filename, file_contents

      return false unless filename.includes?("packages.config")
      file_contents.includes?("Microsoft.AspNet.Mvc")
    end

    def check_routeconfig(filename : String, file_contents : String)
      return unless filename.includes?("RouteConfig.cs")

      if file_contents.includes?(".MapRoute")
        locator = CodeLocator.instance
        locator.set("cs-apinet-mvc-routeconfig", filename)
      end
    end

    def set_name
      @name = "cs_aspnet_mvc"
    end
  end
end
