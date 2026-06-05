require "../../models/tagger"
require "../../models/endpoint"

# Flags WebSocket endpoints — long-lived, bidirectional channels whose
# threat model (origin checks on the handshake, per-message authz, no
# CSRF token on the upgrade) differs from a request/response route.
class WebsocketTagger < Tagger
  # AsyncAPI specs carry the raw server protocol (`ws`, `wss`,
  # `websocket`); HTTP analyzers set `ws`. Accept every spelling so
  # `wss`/`websocket` endpoints aren't missed.
  WS_PROTOCOLS = Set{"ws", "wss", "websocket"}

  # Handshake headers that appear essentially *only* in a WebSocket
  # upgrade, so a single one is conclusive. `Sec-WebSocket-Key` (client)
  # and `Sec-WebSocket-Accept` (server) are reserved for the handshake.
  STRONG_HEADERS = Set{"sec_websocket_key", "sec_websocket_accept"}

  # Also part of the handshake but individually a touch less conclusive;
  # two together flag the endpoint.
  WEAK_HEADERS = Set{
    "sec_websocket_version", "sec_websocket_protocol",
    "sec_websocket_extensions",
  }

  # Transport-library markers that survive in the URL even when the
  # analyzer leaves the protocol as plain HTTP — Socket.IO and SockJS run
  # an HTTP handshake before upgrading, so their routes are emitted as
  # ordinary HTTP endpoints.
  URL_MARKERS = ["socket.io", "sockjs"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "websocket"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      if websocket?(endpoint)
        tag = Tag.new("websocket", "WebSocket endpoint for real-time, bidirectional communication between clients and servers, enabling efficient data exchanges.", "WebSocket")
        endpoint.add_tag(tag)
      end
    end
  end

  private def websocket?(endpoint : Endpoint) : Bool
    return true if WS_PROTOCOLS.includes?(endpoint.protocol.downcase)
    return true if url_marker?(endpoint.url)
    header_websocket?(endpoint)
  end

  private def url_marker?(url : String) : Bool
    lowered = url.downcase
    URL_MARKERS.any? { |marker| lowered.includes?(marker) }
  end

  # A single conclusive handshake header (`Sec-WebSocket-Key`/`-Accept`),
  # an explicit `Upgrade: websocket`, or any two weaker handshake headers
  # mark the endpoint when the protocol metadata is missing.
  private def header_websocket?(endpoint : Endpoint) : Bool
    strong = 0
    weak = 0
    upgrade = false

    endpoint.params.each do |param|
      next unless param.param_type == "header"
      name = param.name.downcase.tr("-", "_")
      if STRONG_HEADERS.includes?(name)
        strong += 1
      elsif WEAK_HEADERS.includes?(name)
        weak += 1
      elsif name == "upgrade" && param.value.downcase.includes?("websocket")
        upgrade = true
      end
    end

    strong >= 1 || upgrade || weak >= 2
  end
end
