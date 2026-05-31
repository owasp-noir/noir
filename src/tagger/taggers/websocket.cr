require "../../models/tagger"
require "../../models/endpoint"

class WebsocketTagger < Tagger
  WORDS        = ["sec-websocket-key", "sec-websocket-accept", "sec-websocket-version"]
  WS_PROTOCOLS = Set{"ws", "wss", "websocket"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "websocket"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      # AsyncAPI specs carry the raw server protocol (`ws`, `wss`,
      # `websocket`), while HTTP analyzers set `ws`. Normalize case and
      # accept all WebSocket protocol spellings so `wss`/`websocket`
      # endpoints aren't missed.
      if WS_PROTOCOLS.includes?(endpoint.protocol.downcase)
        tag = Tag.new("websocket", "WebSocket endpoint for real-time, bidirectional communication between clients and servers, enabling efficient data exchanges.", "WebSocket")
        endpoint.add_tag(tag)
      else
        endpoint.params.each do |param|
          tmp_params.push param.name.to_s.downcase
        end

        words_set = Set.new(WORDS)
        tmp_params_set = Set.new(tmp_params)
        intersection = words_set & tmp_params_set

        # Require at least two WebSocket-related headers to flag the
        # endpoint when the protocol metadata is missing (e.g. for
        # plain HTTP endpoints that happen to mention Sec-WebSocket-*).
        check = intersection.size >= 2

        if check
          tag = Tag.new("websocket", "WebSocket endpoint for real-time, bidirectional communication between clients and servers, enabling efficient data exchanges.", "WebSocket")
          endpoint.add_tag(tag)
        end
      end
    end
  end
end
