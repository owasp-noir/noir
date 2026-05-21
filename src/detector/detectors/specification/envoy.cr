require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Envoy < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless file_contents.includes?("virtual_hosts") && file_contents.includes?("domains")

      if (filename.ends_with?(".yaml") || filename.ends_with?(".yml")) && valid_yaml?(file_contents)
        begin
          data = YAML.parse(file_contents)
          if find_virtual_hosts_yaml(data)
            locator = CodeLocator.instance
            locator.push("envoy-yaml", filename)
            return true
          end
        rescue
        end
      elsif filename.ends_with?(".json") && valid_json?(file_contents)
        begin
          data = JSON.parse(file_contents)
          if find_virtual_hosts_json(data)
            locator = CodeLocator.instance
            locator.push("envoy-json", filename)
            return true
          end
        rescue
        end
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml") || filename.ends_with?(".json")
    end

    def set_name
      @name = "envoy"
    end

    # Registers every matching config path in CodeLocator.
    def idempotent? : Bool
      false
    end

    private def find_virtual_hosts_yaml(data : YAML::Any) : Bool
      # route_config.virtual_hosts (Envoy bootstrap / static config)
      if rc = data["route_config"]?
        if vh = rc["virtual_hosts"]?
          return virtual_hosts_valid_yaml?(vh)
        end
      end

      # virtual_hosts at top level (RDS RouteConfiguration)
      if vh = data["virtual_hosts"]?
        return virtual_hosts_valid_yaml?(vh)
      end

      # xDS resources array: resources[].virtual_hosts
      if resources = data["resources"]?
        if arr = resources.as_a?
          arr.each do |resource|
            if vh = resource["virtual_hosts"]?
              return virtual_hosts_valid_yaml?(vh)
            end
          end
        end
      end

      false
    end

    private def virtual_hosts_valid_yaml?(vh : YAML::Any) : Bool
      if arr = vh.as_a?
        arr.each do |host|
          return true if host["domains"]?
        end
      end
      false
    end

    private def find_virtual_hosts_json(data : JSON::Any) : Bool
      if rc = data["route_config"]?
        if vh = rc["virtual_hosts"]?
          return virtual_hosts_valid_json?(vh)
        end
      end

      if vh = data["virtual_hosts"]?
        return virtual_hosts_valid_json?(vh)
      end

      if resources = data["resources"]?
        if arr = resources.as_a?
          arr.each do |resource|
            if vh = resource["virtual_hosts"]?
              return virtual_hosts_valid_json?(vh)
            end
          end
        end
      end

      false
    end

    private def virtual_hosts_valid_json?(vh : JSON::Any) : Bool
      if arr = vh.as_a?
        arr.each do |host|
          return true if host["domains"]?
        end
      end
      false
    end
  end
end
