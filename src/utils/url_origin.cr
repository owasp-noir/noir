require "uri"

# The origin (scheme + host + port) of a URL, used to decide whether two URLs
# address the same server. Delivery uses it to keep the user's
# `--probe-header` secrets pinned to the `--url` target.
module Noir::UrlOrigin
  # Ports that are implied by the scheme, so `https://api.test` and
  # `https://api.test:443` compare equal.
  DEFAULT_PORTS = {"http" => 80, "https" => 443, "ws" => 80, "wss" => 443}

  # `scheme://host[:port]`, downcased, or nil when the URL names no host —
  # a bare path (`/users`), an empty string, junk that will not parse. A
  # host-less URL has no origin to compare, and callers treat that as
  # "unknown" rather than as a match.
  #
  # A scheme-less authority (`example.com/x`, which `-u` accepts) parses as
  # a path with no host, so it gets one parse attempt with `http://`
  # prepended — the same accommodation the OAS builder makes for `-u`.
  def self.of(url : String?) : String?
    return if url.nil?
    raw = url.strip
    return if raw.empty?

    origin = parse_origin(raw)
    return origin if origin

    # Only worth a second attempt when the value looks like an authority
    # rather than a path: `/users` must stay origin-less.
    return if raw.starts_with?('/') || raw.includes?("://")
    parse_origin("http://#{raw}")
  end

  private def self.parse_origin(raw : String) : String?
    uri = URI.parse(raw)
    host = uri.host
    return if host.nil? || host.empty?

    scheme = (uri.scheme || "http").downcase
    port = uri.port
    port = nil if port && DEFAULT_PORTS[scheme]? == port

    port ? "#{scheme}://#{host.downcase}:#{port}" : "#{scheme}://#{host.downcase}"
  rescue URI::Error
    nil
  end
end
