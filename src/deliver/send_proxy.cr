require "crest"
require "../utils/wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendWithProxy < Deliver
  def run(endpoints : Array(Endpoint))
    proxy_url = URI.parse(@proxy)
    applied_endpoints = apply_all(endpoints)
    wg = WaitGroup.new

    applied_endpoints.each do |endpoint|
      wg.add(1)
      spawn do
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
              p_addr: proxy_url.host,
              p_port: proxy_url.port,
              tls: OpenSSL::SSL::Context::Client.insecure,
              user_agent: "Noir/#{Noir::VERSION}",
              params: endpoint_hash["query"],
              headers: @headers,
              form: body,
              json: is_json
            )
          else
            Crest::Request.execute(
              method: get_symbol(endpoint.method),
              url: endpoint.url,
              p_addr: proxy_url.host,
              p_port: proxy_url.port,
              headers: @headers,
              tls: OpenSSL::SSL::Context::Client.insecure,
              user_agent: "Noir/#{Noir::VERSION}"
            )
          end
        rescue
        ensure
          wg.done
        end
      end
    end

    wg.wait
  end
end
