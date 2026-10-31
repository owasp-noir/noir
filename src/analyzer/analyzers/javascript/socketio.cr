require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/js_handler_resolver"
require "../../../detector/detectors/javascript/socketio"

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
    analyzer_for "js_socketio"

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

    # Any `<recv>.on("event", ...)` handler, or `<recv>.on(prefix + "event"`
    # with the prefix a string constant of the file (group 2).
    EVENT_HANDLER = /\b(\w+)\.on\(\s*(?:([A-Za-z_$][\w$]*)\s*\+\s*)?["']([^"']+)["']/

    # `const prefix = "cloudflared_";`
    STRING_CONST = /^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*["']([^"'\\]*)["']\s*;?\s*$/m

    # Socket.IO / EventEmitter reserved events that are lifecycle signals,
    # not client-invocable application messages.
    RESERVED_EVENTS = Set{
      "connection", "connect", "connect_error", "disconnect", "disconnecting",
      "error", "new_namespace", "newListener", "removeListener",
      "ping", "pong", "reconnect", "reconnect_attempt", "reconnect_error",
      "reconnect_failed", "reconnecting",
    }

    # `registerChatHandlers(socket)` / `generalSocketHandler(socket, server)`
    # inside a connection callback: the socket handed to a function whose
    # definition (often in another module) registers the events. Group 1 is
    # the callee as written, group 2 its first argument.
    DELEGATION = /(?<![\w$.])([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*\(\s*([A-Za-z_$][\w$]*)\s*[,)]/

    # How many hand-offs to follow (`connection` → `registerAll(socket)` →
    # `registerChat(socket)`).
    MAX_DELEGATION_DEPTH = 3

    # {caller file, callee as written, namespace of the connection block}
    alias Delegation = Tuple(String, String, String)

    def analyze
      delegations = [] of Delegation
      parallel_file_scan do |path|
        content = read_file_content(path)
        next unless socketio_evidence?(content)
        # `socket.on(...)` in a test drives its own throwaway server.
        # Import-blind: `test_stub_only?` takes an HTTP-client import
        # (axios/node-fetch) for "not a server" and would drop a standalone
        # Socket.IO service that has no http-server import of its own.
        next if Noir::JSRouteExtractor.test_file?(path, content)
        scan_file(Noir::JSRouteExtractor.strip_js_comments(content), path, delegations)
      end
      follow_delegations(delegations)
      @result
    end

    # A file that imports the server package, or one that runs a connection
    # callback and speaks Socket.IO's own API (`socket.emit(`,
    # `io.to(room).emit(`, `.of("/ns")`). The server is often built in one
    # module and its `io` handed to another (`const io = server.io`), which
    # then imports nothing from `socket.io`. A `ws` server's connection
    # callback writes with `.send(` and has none of that API.
    private def socketio_evidence?(content : String) : Bool
      return true if content.matches?(/from\s+['"]socket\.io['"]|require\(\s*['"]socket\.io['"]\s*\)/)
      return false unless content.includes?(".on(")
      return true if content.includes?("new Server(")
      content.matches?(CONNECTION_HANDLER) && content.matches?(Detector::Javascript::SocketIO::SOCKET_IO_API)
    end

    # The events a connection callback registers through a function it hands
    # the socket to: resolve that function (same file, or the module it was
    # imported from), bind its first parameter as the socket and read its
    # body the way a connection callback is read. Followed a few hops deep,
    # each definition once per namespace.
    private def follow_delegations(delegations : Array(Delegation))
      visited = Set(Tuple(String, Int32, String)).new
      seen = Set(String).new
      MAX_DELEGATION_DEPTH.times do
        break if delegations.empty?
        next_round = [] of Delegation
        delegations.uniq.each do |caller_path, callee, namespace|
          isolating_file_errors(caller_path) do
            handler = Noir::JSHandlerResolver.resolve(callee, read_file_content(caller_path), caller_path) || next
            def_path = handler.path || next
            def_line = handler.line || next
            next unless visited.add?({def_path, def_line, namespace})
            scan_delegate(def_path, def_line, namespace, seen, next_round)
          end
        end
        delegations = next_round
      end
    end

    private def scan_delegate(path : String, line : Int32, namespace : String, seen : Set(String), delegations : Array(Delegation))
      content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
      socket = Noir::JSRouteExtractor.definition_params(content, line).try(&.first?).presence || return
      body = Noir::JSRouteExtractor.definition_body(content, line)
      return unless body.includes?(socket)
      line_start = 0
      (line - 1).times { line_start = (content.byte_index('\n', line_start) || return) + 1 }
      # The body is a slice of the definition: find it from there to number
      # its lines.
      offset = content.byte_index(body, line_start) || return
      first_line = content.byte_slice(0, offset).count('\n') + 1
      body.each_line.with_index do |text, index|
        each_event(text, content) do |recv, event|
          next unless recv == socket
          url = build_url(namespace, event)
          next unless seen.add?("#{path}\0#{url}")
          @result << build_endpoint(url, path, first_line + index)
        end
        collect_delegations(text, Set{socket}, path, namespace, delegations)
      end
    end

    # Each non-reserved `{receiver, event}` registered on `line`. A prefixed
    # name whose prefix is not a string constant of `content` is skipped
    # rather than guessed.
    private def each_event(line : String, content : String, &)
      line.scan(EVENT_HANDLER) do |em|
        event = em[3]
        if prefix = em[2]?
          value = nil
          content.scan(STRING_CONST) { |cm| value = cm[2] if cm[1] == prefix }
          next unless value
          event = value + event
        end
        next if RESERVED_EVENTS.includes?(event)
        yield em[1], event
      end
    end

    private def collect_delegations(line : String, socket_vars : Set(String), path : String, namespace : String, delegations : Array(Delegation))
      return if socket_vars.empty?
      line.scan(DELEGATION) do |dm|
        delegations << {path, dm[1], namespace} if socket_vars.includes?(dm[2])
      end
    end

    private def scan_file(content : String, path : String, delegations : Array(Delegation))
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
        each_event(line, content) do |recv, event|
          next unless socket_vars.includes?(recv)
          url = build_url(current_ns, event)
          next unless seen.add?(url)
          @result << build_endpoint(url, path, line_no)
        end
        collect_delegations(line, socket_vars, path, current_ns, delegations)
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
