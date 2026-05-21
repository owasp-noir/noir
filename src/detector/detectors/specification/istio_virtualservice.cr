require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class IstioVirtualservice < Detector
    ISTIO_API_PREFIX = "networking.istio.io/"

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless valid_yaml_documents?(file_contents)
      return false unless virtual_service_present?(file_contents)

      CodeLocator.instance.push("istio-virtualservice-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "istio_virtualservice"
    end

    # Registers each VirtualService manifest path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def valid_yaml_documents?(content : String) : Bool
      YAML.parse_all(content)
      true
    rescue
      false
    end

    private def virtual_service_present?(content : String) : Bool
      content.includes?(ISTIO_API_PREFIX) && content.includes?("kind: VirtualService")
    end
  end
end
