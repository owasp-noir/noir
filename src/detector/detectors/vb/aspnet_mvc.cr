require "../../../models/detector"

module Detector::VB
  class AspNetMvc < Detector
    detector_for "vb_aspnet_mvc", extensions: %w[.vb]

    # VB projects import `System.Web.Mvc` / `System.Web.Http` project-wide
    # from the `.vbproj`, so a controller file rarely names the namespace;
    # the `*Controller` class with a controller base is the signal.
    CONTROLLER_RE  = /\bClass\s+\w+Controller\b[\s:]*Inherits\s+[\w.]*Controller(?:Base)?\b/i
    ROUTE_TABLE_RE = /\.Map(?:Http|Controller)?Route\s*\(/i

    def detect(filename : String, file_contents : String) : Bool
      content_matches?(file_contents, CONTROLLER_RE) || content_matches?(file_contents, ROUTE_TABLE_RE)
    end
  end
end
