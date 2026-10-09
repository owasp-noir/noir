require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Ocelot < Detector
    # Registers each Ocelot gateway config (`ocelot.json`, `ocelot.<env>.json`,
    # or any JSON carrying Ocelot routes) in `CodeLocator`.
    detector_for "ocelot", extensions: %w[.json], idempotent: false

    # `UpstreamPathTemplate` is Ocelot's own key name; nothing else uses it.
    MARKER = /"UpstreamPathTemplate"/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless content_matches?(file_contents, MARKER)
      return false unless root = json_any?(strip_jsonc(file_contents)).try(&.as_h?)

      found = {"Routes", "ReRoutes", "Aggregates"}.any? do |key|
        root[key]?.try(&.as_a?).try(&.any? { |route| route.as_h?.try(&.["UpstreamPathTemplate"]?.try(&.as_s?)) })
      end
      CodeLocator.instance.push(Noir::LocatorKeys::OCELOT_SPEC, filename) if found
      !!found
    end
  end
end
