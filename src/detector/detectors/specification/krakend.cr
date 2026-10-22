require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Krakend < Detector
    # Registers each KrakenD gateway config (`krakend.json`) in `CodeLocator`.
    detector_for "krakend", extensions: %w[.json], idempotent: false

    ENDPOINTS_MARKER = /"endpoints"/
    BACKEND_MARKER   = /"backend"/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless content_matches?(file_contents, ENDPOINTS_MARKER) && content_matches?(file_contents, BACKEND_MARKER)
      return false unless root = json_any?(file_contents).try(&.as_h?)
      return false unless root["version"]?.try(&.as_i?)

      found = root["endpoints"]?.try(&.as_a?).try(&.any? do |endpoint|
        endpoint.as_h?.try { |e| e["endpoint"]?.try(&.as_s?) && e["backend"]?.try(&.as_a?) }
      end)
      CodeLocator.instance.push(Noir::LocatorKeys::KRAKEND_SPEC, filename) if found
      !!found
    end
  end
end
