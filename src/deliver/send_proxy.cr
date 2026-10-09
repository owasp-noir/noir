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
      @logger.error "--probe-via '#{Noir::Redact.url(@proxy)}' does not resolve to a proxy host and port — expected e.g. http://127.0.0.1:8080. Skipping proxy delivery rather than sending probes directly to the target."
      return
    end
    proxy_host, proxy_port = resolved

    # Redirects matter even more here than for SendReq: the point of proxy
    # delivery is that the proxy sees exactly the endpoints noir discovered,
    # and following a Location pollutes the history with requests noir never
    # found.
    #
    # Proxy delivery targets an intercepting proxy (Burp/ZAP) that presents
    # its own certificate, so verification is intentionally off here
    # regardless of --tls-skip-verify — otherwise every replayed request
    # would fail the handshake against the proxy's cert.
    failed = probe_all(endpoints, OpenSSL::SSL::Context::Client.insecure, "proxy delivery", proxy_host, proxy_port)

    # Counts only requests that never reached the proxy — see SendReq#run.
    @logger.warning "Proxy delivery: #{failed} request(s) could not be sent (run with --debug for details)." if failed > 0
  end
end
