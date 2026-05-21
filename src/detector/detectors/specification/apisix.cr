require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Apisix < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".json") && valid_json?(file_contents)
        data = JSON.parse(file_contents)
        if apisix_routes_json?(data)
          CodeLocator.instance.push("apisix-json", filename)
          return true
        end
      elsif (filename.ends_with?(".yaml") || filename.ends_with?(".yml")) && valid_yaml?(file_contents)
        data = YAML.parse(file_contents)
        if apisix_routes_yaml?(data)
          CodeLocator.instance.push("apisix-yaml", filename)
          return true
        end
      end

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
      has_path = route_obj["uri"]?.try(&.as_s?).to_s != "" ||
                 route_obj["uris"]?.try(&.as_a?).try(&.any? { |u| u.as_s?.to_s != "" }) == true
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
      has_path = route_obj[YAML::Any.new("uri")]?.try(&.as_s?).to_s != "" ||
                 route_obj[YAML::Any.new("uris")]?.try(&.as_a?).try(&.any? { |u| u.as_s?.to_s != "" }) == true
      return false unless has_path
      route_obj[YAML::Any.new("upstream_id")]? != nil ||
        route_obj[YAML::Any.new("plugins")]?.try(&.as_h?).try(&.empty?) == false
    end
  end
end
