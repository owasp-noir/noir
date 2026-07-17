require "crest"
require "wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendWithProxy < Deliver
  def run(endpoints : Array(Endpoint))
    proxy_url = URI.parse(@proxy)
    applied_endpoints = apply_all(endpoints)
    wg = WaitGroup.new
    failures = Atomic(Int32).new(0)
    # Proxy delivery targets an intercepting proxy (Burp/ZAP) that presents
    # its own certificate, so verification is intentionally off here
    # regardless of --tls-skip-verify — otherwise every replayed request
    # would fail the handshake against the proxy's cert.
    proxy_tls = OpenSSL::SSL::Context::Client.insecure

    applied_endpoints.each do |endpoint|
      next if endpoint.non_http? # can't replay an app deep link or CLI command through an HTTP proxy
      requestable_http_methods(endpoint.method).each do |request_method|
        wg.add(1)
        spawn do
          begin
            if !endpoint.params.empty?
              endpoint_hash = endpoint.params_to_hash
              is_json = false
              body = if !endpoint_hash["json"].empty?
                       is_json = true
                       endpoint_hash["json"]
                     else
                       endpoint_hash["form"]
                     end

              Crest::Request.execute(
                method: get_symbol(request_method),
                url: endpoint.url,
                p_addr: proxy_url.host,
                p_port: proxy_url.port,
                tls: proxy_tls,
                user_agent: "Noir/#{Noir::VERSION}",
                params: endpoint_hash["query"],
                headers: @headers,
                form: body,
                json: is_json
              )
            else
              Crest::Request.execute(
                method: get_symbol(request_method),
                url: endpoint.url,
                p_addr: proxy_url.host,
                p_port: proxy_url.port,
                headers: @headers,
                tls: proxy_tls,
                user_agent: "Noir/#{Noir::VERSION}"
              )
            end
          rescue e
            failures.add(1)
            @logger.debug "Exception during proxy delivery"
            @logger.debug_sub e
          ensure
            wg.done
          end
        end
      end
    end

    wg.wait

    failed = failures.get
    @logger.warning "Proxy delivery: #{failed} request(s) failed (run with --debug for details)." if failed > 0
  end
end
