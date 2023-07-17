require "crest"
require "../utils/http_symbols"

def send_req(endpoints : Array(Endpoint))
  endpoints.each do |endpoint|
    begin
      if endpoint.params.size > 0
        endpoint_hash = endpoint.params_to_hash
        body = {} of String => String
        is_json = false
        if endpoint_hash["json"].size > 0
          is_json = true
          body = endpoint_hash["json"]
        else
          body = endpoint_hash["form"]
        end

        Crest::Request.execute(
          method: get_symbol(endpoint.method),
          url: endpoint.url,
          tls: OpenSSL::SSL::Context::Client.insecure,
          user_agent: "Noir/#{Noir::VERSION}",
          params: endpoint_hash["query"],
          form: body,
          json: is_json
        )
      else
        Crest::Request.execute(
          method: get_symbol(endpoint.method),
          url: endpoint.url,
          tls: OpenSSL::SSL::Context::Client.insecure,
          user_agent: "Noir/#{Noir::VERSION}"
        )
      end
    rescue
    end
  end
end
