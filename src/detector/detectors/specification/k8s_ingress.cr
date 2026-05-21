require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class K8sIngress < Detector
    INGRESS_API_VERSION_PREFIX = "networking.k8s.io/"

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless valid_yaml_documents?(file_contents)
      return false unless ingress_present?(file_contents)

      CodeLocator.instance.push("k8s-ingress-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "k8s_ingress"
    end

    # Registers each ingress manifest path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def valid_yaml_documents?(content : String) : Bool
      YAML.parse_all(content)
      true
    rescue
      false
    end

    private def ingress_present?(content : String) : Bool
      # Cheap pre-check: the manifest must declare both an Ingress kind
      # and a networking.k8s.io apiVersion. Tags / Helm templates with
      # `{{ ... }}` interpolation often leave the spec intact while
      # breaking strict YAML parsing — the substring guard tolerates
      # that without us needing to repair the document.
      content.includes?(INGRESS_API_VERSION_PREFIX) && content.includes?("kind: Ingress")
    end
  end
end
