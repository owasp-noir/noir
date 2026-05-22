require "crest"
require "../utils/http_symbols"
require "../models/deliver"

class SendElasticSearch < Deliver
  def run(endpoints : Array(Endpoint), es_endpoint : String)
    uri = URI.parse es_endpoint
    if uri.port.nil?
      uri.port = 9200
    end

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

    # Use `body:` (raw payload) rather than `form:` (URL-encoded). The
    # payload is a JSON document and ES rejects form-encoded JSON.
    Crest::Request.execute(
      method: :post,
      url: uri.to_s,
      tls: OpenSSL::SSL::Context::Client.insecure,
      user_agent: "Noir/#{Noir::VERSION}",
      body: body,
      headers: es_headers,
      json: true
    )
  rescue e
    @logger.debug "Exception of ES Delivery"
    @logger.debug_sub e
  end
end
