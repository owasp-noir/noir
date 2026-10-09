require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Yarp < Detector
    # Registers YARP (`Yarp.ReverseProxy`) route config in `CodeLocator`: the
    # `ReverseProxy` section of `appsettings*.json` (or any JSON config file),
    # and C# files that build `RouteConfig`s in code.
    detector_for "yarp", extensions: %w[.json .cs], idempotent: false

    JSON_MARKER = /"ReverseProxy"/
    # `RouteConfig` alone is also ASP.NET MVC's route-registration class;
    # `RouteMatch` and the configuration namespace are YARP's.
    CODE_MARKER = /\bnew\s+RouteMatch\b|\bYarp\.ReverseProxy\.Configuration\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      found = if filename.ends_with?(".cs")
                content_matches?(file_contents, CODE_MARKER)
              else
                content_matches?(file_contents, JSON_MARKER) && yarp_routes?(filename, file_contents)
              end
      CodeLocator.instance.push(Noir::LocatorKeys::YARP_SPEC, filename) if found
      found
    end

    private def yarp_routes?(filename : String, content : String) : Bool
      root = begin
        parse_json_lenient(strip_jsonc(content)).as_h?
      rescue e
        record_unparsable_document(filename, e)
        nil
      end
      return false unless root
      routes = root["ReverseProxy"]?.try(&.as_h?).try(&.["Routes"]?)
      !!(routes.try(&.as_h?).try(&.present?) || routes.try(&.as_a?).try(&.present?))
    end
  end
end
