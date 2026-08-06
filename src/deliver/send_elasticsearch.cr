require "crest"
require "../utils/http_symbols"
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

  def run(endpoints : Array(Endpoint), es_endpoint : String)
    uri = SendElasticSearch.normalize_endpoint(es_endpoint)

    applied_endpoints = apply_all(endpoints)

    body = {
      "endpoints" => applied_endpoints,
    }.to_json

    # Dup the user-supplied headers before adding ES-specific
    # Content-Type / Accept so the mutation doesn't bleed into
    # @headers. The original code mutated `es_headers` (an alias of
    # @headers) but then passed `@headers` to Crest, which only worked
    # because both names pointed at the same Hash. Be explicit instead.
    es_headers = @headers.dup
    es_headers["Content-Type"] = "application/json"
    es_headers["Accept"] = "application/json"

    # Crest's `Request.execute` only recognizes `form:` as the body
    # source — `body:` is silently swallowed into `**options` and the
    # request goes out with Content-Length: 0. Combined with
    # `json: true`, `form:` ships the raw String through as the JSON
    # payload (verified against Crest 1.4.x in spec).
    Crest::Request.execute(
      method: :post,
      url: uri.to_s,
      tls: tls_context,
      user_agent: "Noir/#{Noir::VERSION}",
      form: body,
      headers: es_headers,
      json: true,
      connect_timeout: export_connect_timeout,
      read_timeout: export_read_timeout
    )
  rescue e
    # Surface the failure at warning level so an indexing outage isn't
    # mistaken for a successful export. Reported against the URL the user
    # passed: `URI.parse` itself can raise, and the local `uri` is then nil,
    # which rendered the message as "delivery to  failed".
    @logger.warning "Elasticsearch delivery to #{es_endpoint} failed: #{e.message}"
    @logger.debug_sub e
  end
end
