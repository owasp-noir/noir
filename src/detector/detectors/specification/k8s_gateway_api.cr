require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class K8sGatewayApi < Detector
    GATEWAY_API_PREFIX = "gateway.networking.k8s.io/"

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless valid_yaml_documents?(file_contents)
      return false unless route_present?(file_contents)

      CodeLocator.instance.push("k8s-gateway-api-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "k8s_gateway_api"
    end

    # Registers each Gateway API manifest path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def valid_yaml_documents?(content : String) : Bool
      YAML.parse_all(content)
      true
    rescue
      false
    end

    private def route_present?(content : String) : Bool
      content.includes?(GATEWAY_API_PREFIX) && content.includes?("kind: HTTPRoute")
    end
  end
end
