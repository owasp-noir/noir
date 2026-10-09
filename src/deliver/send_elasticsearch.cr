require "../models/deliver"

class SendElasticSearch < Deliver
  # `http://` with no port means the local/dev cluster shape, where 9200 is
  # the useful default. `https://` does not: managed clusters (AWS
  # OpenSearch Service, Elastic Cloud) and anything behind a TLS reverse
  # proxy listen on 443, so forcing 9200 there rewrote a working endpoint
  # into an unreachable one and the export failed with a connection error
  # the user had no way to explain. An explicit port always wins.
  def self.normalize_endpoint(es_endpoint : String) : URI
    uri = URI.parse es_endpoint
    uri.port = 9200 if uri.port.nil? && uri.scheme == "http"
    uri
  end

  # Failures are reported against the URL the user passed: `URI.parse`
  # itself can raise, so the normalized URI may never exist.
  def run(endpoints : Array(Endpoint), es_endpoint : String)
    post_export(Noir::Redact.url(es_endpoint), "Elasticsearch", "Elasticsearch") do
      uri = SendElasticSearch.normalize_endpoint(es_endpoint)
      {uri.to_s, {"endpoints" => apply_all(endpoints)}.to_json}
    end
  end
end
