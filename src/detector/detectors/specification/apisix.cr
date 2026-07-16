require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Apisix < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".json")
        return false unless apisix_candidate?(file_contents)

        data = JSON.parse(file_contents)
        if apisix_routes_json?(data)
          CodeLocator.instance.push("apisix-json", filename)
          return true
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        return false unless apisix_candidate?(file_contents)

        data = YAML.parse(file_contents)
        if apisix_routes_yaml?(data)
          CodeLocator.instance.push("apisix-yaml", filename)
          return true
        end
      end

      false
    rescue
      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "apisix"
    end

    # Registers every APISIX route config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def apisix_routes_json?(data : JSON::Any) : Bool
      root = data.as_h?
      return false unless root
      routes = root["routes"]?.try(&.as_a?)
      return false unless routes
      routes.any? { |route| route_has_signature_json?(route) }
    end

    private def route_has_signature_json?(route : JSON::Any) : Bool
      route_obj = route.as_h?
      return false unless route_obj
      has_path = non_empty_json_string?(route_obj["uri"]?) ||
                 route_obj["uris"]?.try(&.as_a?).try(&.any? { |uri| non_empty_json_string?(uri) }) == true
      return false unless has_path
      route_obj["upstream_id"]? != nil || route_obj["plugins"]?.try(&.as_h?).try(&.empty?) == false
    end

    private def apisix_routes_yaml?(data : YAML::Any) : Bool
      root = data.as_h?
      return false unless root
      routes = root[YAML::Any.new("routes")]?.try(&.as_a?)
      return false unless routes
      routes.any? { |route| route_has_signature_yaml?(route) }
    end

    private def route_has_signature_yaml?(route : YAML::Any) : Bool
      route_obj = route.as_h?
      return false unless route_obj
      has_path = non_empty_yaml_string?(route_obj[YAML::Any.new("uri")]?) ||
                 route_obj[YAML::Any.new("uris")]?.try(&.as_a?).try(&.any? { |uri| non_empty_yaml_string?(uri) }) == true
      return false unless has_path
      route_obj[YAML::Any.new("upstream_id")]? != nil ||
        route_obj[YAML::Any.new("plugins")]?.try(&.as_h?).try(&.empty?) == false
    end

    private def non_empty_json_string?(value : JSON::Any?) : Bool
      non_empty_text?(value.try(&.as_s?))
    end

    private def non_empty_yaml_string?(value : YAML::Any?) : Bool
      non_empty_text?(value.try(&.as_s?))
    end

    private def non_empty_text?(text : String?) : Bool
      !!(text && !text.empty?)
    end

    # Word-bounded guard markers. The accepted shapes require actual
    # `routes` / `uri`(`uris`) / `upstream_id` or `plugins` keys, which
    # always appear word-bounded in the raw document (`"uri":` / `uri:`),
    # so `\b` keeps the guard a necessary condition while no longer
    # tripping on substrings — the bare `includes?("uri")` matched
    # "security" and made large OpenAPI JSON specs pay a full redundant
    # parse here on every scan (this detector is non-idempotent).
    ROUTES_MARKER  = /\broutes\b/
    URI_MARKER     = /\buris?\b/
    PAYLOAD_MARKER = /\bupstream_id\b|\bplugins\b/

    private def apisix_candidate?(content : String) : Bool
      content.matches?(ROUTES_MARKER) &&
        content.matches?(URI_MARKER) &&
        content.matches?(PAYLOAD_MARKER)
    end
  end
end
