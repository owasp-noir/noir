require "../../engines/javascript_engine"

module Analyzer::Javascript
  # Surfaces Socket.IO real-time attack surface as `ws://` endpoints. A
  # Socket.IO server handles inbound client messages via
  # `socket.on("event", ...)` handlers inside a connection callback;
  # `io.of("/namespace")` scopes handlers to a namespace. Each inbound
  # event becomes one endpoint `ws://<namespace>/<event>` (default
  # namespace → `ws://<event>`), method "SEND", protocol "ws" — so the
  # existing WebsocketTagger tags them. Outbound `emit`/`send` calls
  # (server → client) are not attack surface and are ignored.
  #
  # Per-file line scan (Socket.IO server setup and its handlers are
  # co-located). A namespace cursor tracks which `.of("/ns")` connection
  # block the current `socket.on` handlers belong to.
  class SocketIO < JavascriptEngine
    # `const admin = io.of("/admin")` — binds a variable to a namespace.
    NS_ASSIGN = /\b(\w+)\s*=\s*\w+\.of\(\s*["']([^"']+)["']/

    # A connection handler on an inline namespace: `io.of("/x").on("connection"`.
    NS_INLINE_CONNECTION = /\.of\(\s*["']([^"']+)["']\s*\)\s*\.on\(\s*["'](?:connection|connect)["']/

    # A connection handler on a receiver variable: `admin.on("connection"`.
    CONNECTION_HANDLER = /\b(\w+)\.on\(\s*["'](?:connection|connect)["']/

    # The socket parameter bound by a connection callback:
    # `.on("connection", (socket) => …`, `… , async function (client) {`, etc.
    # Only `.on(...)` calls on such a bound variable are treated as socket
    # event handlers, so unrelated emitters that co-locate with the server
    # (`process.on("SIGTERM")`, `httpServer.on("error")`) don't leak phantom
    # events.
    SOCKET_PARAM = /\.on\(\s*["'](?:connection|connect)["']\s*,\s*(?:async\s+)?(?:function\s*)?\(?\s*(\w+)/

    # Any `<recv>.on("event", ...)` handler.
    EVENT_HANDLER = /\b(\w+)\.on\(\s*["']([^"']+)["']/

    # Socket.IO / EventEmitter reserved events that are lifecycle signals,
    # not client-invocable application messages.
    RESERVED_EVENTS = Set{
      "connection", "connect", "connect_error", "disconnect", "disconnecting",
      "error", "new_namespace", "newListener", "removeListener",
      "ping", "pong", "reconnect", "reconnect_attempt", "reconnect_error",
      "reconnect_failed", "reconnecting",
    }

    def analyze
      parallel_file_scan do |path|
        content = read_file_content(path)
        next unless socketio_evidence?(content)
        scan_file(content, path)
      end
      @result
    end

    private def socketio_evidence?(content : String) : Bool
      content.matches?(/from\s+['"]socket\.io['"]|require\(\s*['"]socket\.io['"]\s*\)/) ||
        (content.includes?("new Server(") && content.includes?(".on("))
    end

    private def scan_file(content : String, path : String)
      current_ns = "/" # default namespace
      ns_vars = {} of String => String
      socket_vars = Set(String).new # params bound by connection callbacks
      # Dedup so a handler registered on two sockets doesn't duplicate.
      seen = Set(String).new

      content.each_line.with_index do |line, index|
        line_no = index + 1

        if m = line.match(NS_ASSIGN)
          ns_vars[m[1]] = m[2]
        end

        # A connection handler moves the namespace cursor and binds the
        # socket parameter; it is never an application event itself.
        if line.matches?(NS_INLINE_CONNECTION) || line.matches?(CONNECTION_HANDLER)
          if m = line.match(NS_INLINE_CONNECTION)
            current_ns = m[1]
          elsif m = line.match(CONNECTION_HANDLER)
            current_ns = ns_vars[m[1]]? || "/"
          end
          if pm = line.match(SOCKET_PARAM)
            socket_vars << pm[1]
          end
          next
        end

        # A `<socket>.on("event")` on a bound socket variable is an inbound
        # client message handler. Receivers that were never bound as a
        # connection socket (`process`, `httpServer`, `io`, …) are ignored.
        line.scan(EVENT_HANDLER) do |em|
          recv = em[1]
          event = em[2]
          next unless socket_vars.includes?(recv)
          next if RESERVED_EVENTS.includes?(event)
          url = build_url(current_ns, event)
          next if seen.includes?(url)
          seen << url
          @result << build_endpoint(url, path, line_no)
        end
      end
    end

    private def build_url(namespace : String, event : String) : String
      surface = namespace.strip.lstrip('/')
      surface.empty? ? "ws://#{event}" : "ws://#{surface}/#{event}"
    end

    private def build_endpoint(url : String, path : String, line : Int32) : Endpoint
      ep = Endpoint.new(url, "SEND", Details.new(PathInfo.new(path, line)))
      ep.protocol = "ws"
      ep
    end
  end
end
