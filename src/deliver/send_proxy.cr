require "crest"
require "wait_group"
require "../utils/http_symbols"
require "../models/deliver"

class SendWithProxy < Deliver
  # Crest's `set_proxy!` is a no-op unless it gets BOTH a host and a port,
  # and it fails open: the request goes out *directly to the target*
  # instead, with no error. Combined with the insecure TLS context below,
  # that shipped `--probe-header` credentials straight to the real host
  # with verification off while the user believed they were watching the
  # traffic in Burp. `--probe-via` is validated at CLI parse time
  # (`normalize_probe_via!`), but options also arrive from a config file
  # and from library callers, so refuse to send at all rather than trust
  # that path.
  #
  # Returns the `{host, port}` pair Crest needs, or nil when the value
  # can't produce both — the case that used to fail open.
  def self.resolve_proxy_target(raw : String) : {String, Int32}?
    uri = begin
      URI.parse(raw)
    rescue URI::Error
      return
    end

    host = uri.host
    port = uri.port
    return if host.nil? || host.empty? || port.nil?
    return unless (1..65535).includes?(port)

    {host, port}
  end

  def run(endpoints : Array(Endpoint))
    resolved = SendWithProxy.resolve_proxy_target(@proxy)
    if resolved.nil?
      @logger.error "--probe-via '#{@proxy}' does not resolve to a proxy host and port — expected e.g. http://127.0.0.1:8080. Skipping proxy delivery rather than sending probes directly to the target."
      return
    end
    proxy_host, proxy_port = resolved

    applied_endpoints = apply_all(endpoints)
    wg = WaitGroup.new
    failures = Atomic(Int32).new(0)
    # Bound in-flight requests to --concurrency (see send_req.cr).
    sem = Channel(Nil).new(concurrency_limit)
    # `handle_errors: false, max_redirects: 0` on every call below — see the
    # comment on SendReq#run for why the two are inseparable. Redirects
    # matter even more here: the point of proxy delivery is that the proxy
    # sees exactly the endpoints noir discovered, and following a Location
    # pollutes the history with requests noir never found.
    #
    # Proxy delivery targets an intercepting proxy (Burp/ZAP) that presents
    # its own certificate, so verification is intentionally off here
    # regardless of --tls-skip-verify — otherwise every replayed request
    # would fail the handshake against the proxy's cert.
    proxy_tls = OpenSSL::SSL::Context::Client.insecure

    applied_endpoints.each do |endpoint|
      next if endpoint.non_http? # can't replay an app deep link or CLI command through an HTTP proxy
      next if skip_probe_target?(endpoint)
      # See send_req.cr — built once per endpoint, outside the spawn.
      request_headers = probe_headers(endpoint)
      requestable_http_methods(endpoint.method).each do |request_method|
        wg.add(1)
        sem.send(nil) # acquire a slot (blocks once concurrency_limit are in flight)
        spawn do
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
              url: probe_url(endpoint, request_method),
              p_addr: proxy_host,
              p_port: proxy_port,
              tls: proxy_tls,
              user_agent: "Noir/#{Noir::VERSION}",
              params: endpoint_hash["query"],
              headers: request_headers,
              form: body,
              json: is_json,
              handle_errors: false,
              max_redirects: 0,
              connect_timeout: probe_connect_timeout,
              read_timeout: probe_read_timeout
            )
          else
            Crest::Request.execute(
              method: get_symbol(request_method),
              url: probe_url(endpoint, request_method),
              p_addr: proxy_host,
              p_port: proxy_port,
              headers: request_headers,
              tls: proxy_tls,
              user_agent: "Noir/#{Noir::VERSION}",
              handle_errors: false,
              max_redirects: 0,
              connect_timeout: probe_connect_timeout,
              read_timeout: probe_read_timeout
            )
          end
        rescue e
          failures.add(1)
          @logger.debug "Exception during proxy delivery"
          @logger.debug_sub e
        ensure
          sem.receive # release the slot
          wg.done
        end
      end
    end

    wg.wait

    # Counts only requests that never reached the proxy — see SendReq#run.
    failed = failures.get
    self.undeliverable_count = failed
    @logger.warning "Proxy delivery: #{failed} request(s) could not be sent (run with --debug for details)." if failed > 0
  end
end
