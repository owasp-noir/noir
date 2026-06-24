require "crest"
require "wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendReq < Deliver
  def run(endpoints : Array(Endpoint))
    applied_endpoints = apply_all(endpoints)
    wg = WaitGroup.new

    applied_endpoints.each do |endpoint|
      next if endpoint.non_http? # can't HTTP-probe an app deep link or CLI command
      requestable_http_methods(endpoint.method).each do |request_method|
        wg.add(1)
        spawn do
          begin
            if endpoint.params.size > 0
              endpoint_hash = endpoint.params_to_hash
              is_json = false
              body = if endpoint_hash["json"].size > 0
                       is_json = true
                       endpoint_hash["json"]
                     else
                       endpoint_hash["form"]
                     end

              Crest::Request.execute(
                method: get_symbol(request_method),
                url: endpoint.url,
                tls: OpenSSL::SSL::Context::Client.insecure,
                user_agent: "Noir/#{Noir::VERSION}",
                params: endpoint_hash["query"],
                form: body,
                headers: @headers,
                json: is_json
              )
            else
              Crest::Request.execute(
                method: get_symbol(request_method),
                url: endpoint.url,
                headers: @headers,
                tls: OpenSSL::SSL::Context::Client.insecure,
                user_agent: "Noir/#{Noir::VERSION}"
              )
            end
          rescue e
            @logger.debug "Exception during request delivery"
            @logger.debug_sub e
          ensure
            wg.done
          end
        end
      end
    end

    wg.wait
  end
end
