require "crest"
require "wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendReq < Deliver
  def run(endpoints : Array(Endpoint))
    applied_endpoints = apply_all(endpoints)
    wg = WaitGroup.new
    tls = tls_context
    failures = Atomic(Int32).new(0)
    # Bound in-flight requests to --concurrency so a large endpoint set can't
    # spawn thousands of sockets at once and hit "Too many open files".
    sem = Channel(Nil).new(concurrency_limit)

    applied_endpoints.each do |endpoint|
      next if endpoint.non_http? # can't HTTP-probe an app deep link or CLI command
      requestable_http_methods(endpoint.method).each do |request_method|
        wg.add(1)
        sem.send(nil) # acquire a slot (blocks once `concurrency_limit` are in flight)
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
                tls: tls,
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
                tls: tls,
                user_agent: "Noir/#{Noir::VERSION}"
              )
            end
          rescue e
            failures.add(1)
            @logger.debug "Exception during request delivery"
            @logger.debug_sub e
          ensure
            sem.receive # release the slot
            wg.done
          end
        end
      end
    end

    wg.wait

    # Individual probe failures stay at debug (many endpoints simply won't
    # respond), but a total-failure count surfaces once so a fully-broken
    # target (bad -u, TLS rejection, network down) isn't mistaken for a
    # clean run.
    failed = failures.get
    @logger.warning "Probe delivery: #{failed} request(s) failed (run with --debug for details)." if failed > 0
  end
end
