require "../../models/tagger"
require "../../models/endpoint"

# Flags SOAP / XML web-service endpoints. SOAP surfaces warrant XML-
# specific review (XXE, SOAP-action spoofing, WS-Security handling) that
# differs from a typical REST/JSON route, so calling them out helps a
# reviewer pick the right lens.
class SoapTagger < Tagger
  # Request headers that mark a SOAP call. `SOAPAction` is mandatory in
  # SOAP 1.1; `Content-Type: application/soap+xml` is the SOAP 1.2 marker.
  HEADER_NAMES = Set{"soapaction"}

  # Unambiguous SOAP / XML-web-service URL markers: WSDL documents and the
  # classic ASP.NET (`.asmx`) handler. A bare `soap` path segment is
  # deliberately *not* matched — it collides with non-SOAP routes
  # (e.g. a `/products/soap` store listing).
  URL_MARKERS = ["?wsdl", ".wsdl", ".asmx"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "soap"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      check = soap_header?(endpoint) || soap_url?(endpoint.url)

      if check
        tag = Tag.new("soap", "SOAP endpoint for XML-based web service communication, supporting structured information exchanges across network applications.", "SOAP")
        endpoint.add_tag(tag)
      end
    end
  end

  private def soap_header?(endpoint : Endpoint) : Bool
    endpoint.params.any? do |param|
      next false unless param.param_type == "header"
      name = param.name.downcase.tr("-", "_")
      next true if HEADER_NAMES.includes?(name)
      name == "content_type" && param.value.downcase.includes?("soap+xml")
    end
  end

  private def soap_url?(url : String) : Bool
    lowered = url.downcase
    URL_MARKERS.any? { |marker| lowered.includes?(marker) }
  end
end
