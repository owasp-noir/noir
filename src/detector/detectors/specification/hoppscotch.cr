require "../../../models/detector"
require "../../../models/code_locator"
require "../../../models/locator_keys"
require "../../../utils/json"

module Detector::Specification
  class Hoppscotch < Detector
    # Registers Hoppscotch collection and environment exports in
    # `CodeLocator`.
    detector_for "hoppscotch", extensions: %w[.json], idempotent: false

    # Every `.json` in the tree reaches these guards.
    # `"requests"` and `"variables"` alone are common (k8s, GraphQL), so
    # each pairs with the key that is specific to its Hoppscotch shape.
    REQUESTS_MARKER  = /"requests"\s*:/
    ENDPOINT_MARKER  = /"endpoint"\s*:/
    VARIABLES_MARKER = /"variables"\s*:/
    SECRET_MARKER    = /"secret"\s*:/

    # A collection export (one object, or an array of them for an
    # all-collections export) reports the tech. An environment export is
    # registered for `<<var>>` resolution but reports nothing on its own,
    # so a stray `{name, variables}` file can never surface the tech.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".json")
      has_requests = content_matches?(file_contents, REQUESTS_MARKER) && content_matches?(file_contents, ENDPOINT_MARKER)
      return false unless has_requests ||
                          (content_matches?(file_contents, VARIABLES_MARKER) && content_matches?(file_contents, SECRET_MARKER))

      doc = json_any?(file_contents)
      return false unless doc
      nodes = doc.as_a? || [doc]
      return false if nodes.empty?

      if has_requests && nodes.all? { |node| collection?(node) }
        CodeLocator.instance.push(Noir::LocatorKeys::HOPPSCOTCH_JSON, filename)
        return true
      end

      if nodes.all? { |node| environment?(node) }
        CodeLocator.instance.push(Noir::LocatorKeys::HOPPSCOTCH_JSON, filename)
      end
      false
    end

    # `{v, folders: [], requests: [{method, endpoint, ...}]}`, nested
    # folders included.
    private def collection?(node : JSON::Any) : Bool
      !!node.as_h?.try(&.has_key?("v")) && collection_folder?(node)
    end

    # Folders written by older Hoppscotch versions omit `v`.
    private def collection_folder?(node : JSON::Any) : Bool
      return false unless node.as_h?
      return false unless requests = node["requests"]?.try(&.as_a?)
      return false unless folders = node["folders"]?.try(&.as_a?)
      requests.all? { |r| r.as_h? && r["endpoint"]?.try(&.as_s?) && r["method"]?.try(&.as_s?) } &&
        folders.all? { |folder| collection_folder?(folder) }
    end

    # `{name, variables: [{key, value, secret}]}` — `secret` is what sets a
    # Hoppscotch environment apart from any other key/value list.
    private def environment?(node : JSON::Any) : Bool
      return false unless node.as_h? && node["name"]?.try(&.as_s?)
      return false unless variables = node["variables"]?.try(&.as_a?)
      !variables.empty? && variables.all? { |var| var.as_h? && var["key"]?.try(&.as_s?) && !var["secret"]?.try(&.as_bool?).nil? }
    end
  end
end
