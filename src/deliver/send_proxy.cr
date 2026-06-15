require "crest"
require "wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendWithProxy < Deliver
  def run(endpoints : Array(Endpoint))
    proxy_url = URI.parse(@proxy)
    applied_endpoints = apply_all(endpoints)
    wg = WaitGroup.new

    applied_endpoints.each do |endpoint|
      next if endpoint.mobile? # can't replay an app deep link through an HTTP proxy
      wg.add(1)
      spawn do
        begin
          unless endpoint.params.empty?
            endpoint_hash = endpoint.params_to_hash
            is_json = false
            body = if !endpoint_hash["json"].empty?
                     is_json = true
                     endpoint_hash["json"]
                   else
                     endpoint_hash["form"]
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
        rescue e
          @logger.debug "Exception during proxy delivery"
          @logger.debug_sub e
        ensure
          wg.done
        end
      end
    end

    wg.wait
  end
end
