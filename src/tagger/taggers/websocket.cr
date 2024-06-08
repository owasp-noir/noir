require "../../models/tagger"
require "../../models/endpoint"

class WebsocketTagger < Tagger
  WORDS = ["sec-websocket-key", "sec-websocket-accept", "sec-websocket-version"]

  def initialize(options : Hash(String, String))
    super
    @name = "websocket"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      if endpoint.protocol == "ws"
        tag = Tag.new("websocket", "WebSocket endpoint for real-time, bidirectional communication between clients and servers, enabling efficient data exchanges.", "WebSocket")
        endpoint.add_tag(tag)
      else
        endpoint.params.each do |param|
          tmp_params.push param.name.to_s.downcase
        end

        words_set = Set.new(WORDS)
        tmp_params_set = Set.new(tmp_params)
        intersection = words_set & tmp_params_set

        # Check that at least three parameters match.
        check = intersection.size.to_i >= 2

        if check
          tag = Tag.new("websocket", "WebSocket endpoint for real-time, bidirectional communication between clients and servers, enabling efficient data exchanges.", "WebSocket")
          endpoint.add_tag(tag)
        end
      end
    end
  end
end
