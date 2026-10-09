require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Apigee < Detector
    # Registers Apigee proxy endpoints (`apiproxy/proxies/*.xml`) in
    # `CodeLocator`. Target endpoints and policies carry neither marker.
    detector_for "apigee", extensions: %w[.xml], idempotent: false

    PROXY_ENDPOINT = /<ProxyEndpoint\b/
    CONNECTION     = /<HTTPProxyConnection\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      found = content_matches?(file_contents, PROXY_ENDPOINT) && content_matches?(file_contents, CONNECTION)
      CodeLocator.instance.push(Noir::LocatorKeys::APIGEE_PROXY, filename) if found
      found
    end
  end
end
