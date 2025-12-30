require "../../../models/detector"

module Detector::CSharp
  class AspNetMvc < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("Microsoft.AspNet.Mvc")
      check = check && filename.includes?("packages.config")
      check_routeconfig filename, file_contents

      check
    end

    def check_routeconfig(filename : String, file_contents : String)
      check = file_contents.includes?(".MapRoute")
      check = check && filename.includes?("RouteConfig.cs")
      if check
        locator = CodeLocator.instance
        locator.set("cs-apinet-mvc-routeconfig", filename)
      end
    end

    def set_name
      @name = "cs_aspnet_mvc"
    end
  end
end
