require "crest"
require "wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendReq < Deliver
  # Every probe goes out with `handle_errors: false, max_redirects: 0`.
  # The two belong together and neither is optional:
  #
  # `handle_errors` defaults to true in Crest, which raises
  # `Crest::RequestFailed` on any non-2xx. A probe's whole job is to fire
  # the request — a 404 or a 500 is a delivered probe, not a delivery
  # failure. Left on, it fed the `failures` counter below, and since path
  # templates like `/users/{id}` are probed literally, most probes against
  # a real app 404. The "N request(s) failed" line then fired en masse and
  # buried the case it exists for: a genuinely broken target (bad -u, TLS
  # rejection, network down).
  #
  # `max_redirects: 0` must be set alongside it, not alone —
  # `Redirector#check_max_redirects` raises when
  # `max_redirects <= 0 && handle_errors`, so setting it by itself turns
  # every 3xx into a counted failure and makes things worse. Redirects are
  # off because Crest copies the request headers onto the redirected
  # request, including a `--probe-header` Authorization token, and follows
  # absolute Locations to other hosts. Beyond the credential leak,
  # following them generates traffic to URLs noir never discovered, which
  # is not what "replay my endpoints" means.
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
                json: is_json,
                handle_errors: false,
                max_redirects: 0
              )
            else
              Crest::Request.execute(
                method: get_symbol(request_method),
                url: endpoint.url,
                headers: @headers,
                tls: tls,
                user_agent: "Noir/#{Noir::VERSION}",
                handle_errors: false,
                max_redirects: 0
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

    # Individual failures stay at debug, but a total count surfaces once so
    # a fully-broken target (bad -u, TLS rejection, network down) isn't
    # mistaken for a clean run. With `handle_errors: false` above this now
    # counts only requests that never completed — a 404/500 response is a
    # delivered probe and no longer lands here.
    failed = failures.get
    self.undeliverable_count = failed
    @logger.warning "Probe delivery: #{failed} request(s) could not be sent (run with --debug for details)." if failed > 0
  end
end
