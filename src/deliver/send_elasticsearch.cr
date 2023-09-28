require "crest"
require "../utils/http_symbols"
require "../models/deliver"

class SendElasticSearch < Deliver
  def run(endpoints : Array(Endpoint), es_endpoint : String)
    uri = URI.parse es_endpoint
    if uri.port.nil?
      uri.port = 9200
    end

    body = {
      "endpoints" => endpoints,
    }.to_json
    es_headers = @headers
    es_headers["Content-Type"] = "application/json"
    es_headers["Accept"] = "application/json"

    begin
      Crest::Request.execute(
        method: :post,
        url: uri.to_s,
        tls: OpenSSL::SSL::Context::Client.insecure,
        user_agent: "Noir/#{Noir::VERSION}",
        form: body,
        headers: @headers,
        json: true
      )
    rescue e
      @logger.debug e
    end
  rescue
  end
end
