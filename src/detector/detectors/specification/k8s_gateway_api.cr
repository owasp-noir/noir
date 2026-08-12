require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class K8sGatewayApi < Detector
    # Registers each Gateway API manifest path in `CodeLocator`.
    detector_for "k8s_gateway_api", extensions: %w[.yaml .yml], idempotent: false

    # Every `.yaml`/`.yml` in the tree reaches these guards. Both must
    # match, so they stay separate probes rather than a union.
    GATEWAY_API_PREFIX_MARKER = /gateway\.networking\.k8s\.io\//
    # `kind: "HTTPRoute"` is as valid as the bare form and is what Helm charts
    # and generators emit; the marker has to allow the quotes or the whole
    # manifest is dropped before the parse ever runs.
    HTTP_ROUTE_KIND_MARKER = /kind:[ \t]*["']?HTTPRoute/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      # Substring guard first: the full `YAML.parse_all` below only runs on
      # the rare manifest that actually mentions the Gateway API, instead of
      # on every YAML file of the scan (this detector is non-idempotent, so
      # there is no early-exit). Both checks must pass, so the order is free.
      return false unless route_present?(file_contents)
      return false unless valid_yaml_documents?(file_contents)

      CodeLocator.instance.push(Noir::LocatorKeys::K8S_GATEWAY_API_SPEC, filename)
      true
    end

    private def valid_yaml_documents?(content : String) : Bool
      YAML.parse_all(content)
      true
    rescue
      false
    end

    private def route_present?(content : String) : Bool
      content_matches?(content, GATEWAY_API_PREFIX_MARKER) && content_matches?(content, HTTP_ROUTE_KIND_MARKER)
    end
  end
end
