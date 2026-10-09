require "../../../models/detector"
require "../../../models/code_locator"
require "../../../models/locator_keys"
require "../../../utils/json"

module Detector::Specification
  class ThunderClient < Detector
    # Registers Thunder Client request files under `thunder-tests/` in
    # `CodeLocator`.
    detector_for "thunder_client", path_segments: %w[thunder-tests/], idempotent: false

    URL_MARKER = /"url"\s*:/

    # `thunderclient.json` is an array of requests; `collections/*.json` is
    # a collection object (or array) with a `requests` array. Either way at
    # least one `{_id, url, method}` request must be present, so the
    # collection/environment metadata files never report the tech.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".json") && applicable?(filename)
      return false unless content_matches?(file_contents, URL_MARKER)
      return false unless doc = json_any?(file_contents)

      nodes = doc.as_a? || [doc]
      found = nodes.any? do |node|
        next false unless node.as_h?
        candidates = node["requests"]?.try(&.as_a?) || [node]
        candidates.any? { |r| r.as_h? && r["_id"]? && r["url"]?.try(&.as_s?) && r["method"]?.try(&.as_s?) }
      end
      return false unless found

      CodeLocator.instance.push(Noir::LocatorKeys::THUNDER_CLIENT_JSON, filename)
      true
    end
  end
end
