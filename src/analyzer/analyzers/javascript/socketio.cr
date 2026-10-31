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
    # (the prefix variable is group 2).
    EVENT_HANDLER = /\b(\w+)\.on\(\s*(?:([A-Za-z_$][\w$]*)\s*\+\s*)?["']([^"']+)["']/

    # `const prefix = "cloudflared_";` (group 1 the keyword).
    STRING_CONST = /^\s*(?:export\s+)?(const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*["']([^"'\\]*)["']\s*;?\s*$/m

    # A Node `net` / `tls` / `dgram` server: its connection callback's socket
    # emits `data` and `end`, not Socket.IO events.
    NODE_SOCKET_SERVER = /(?:require\(\s*|\bfrom\s+)['"](?:node:)?(?:net|tls|dgram)['"]/

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
      content.matches?(CONNECTION_HANDLER) && content.matches?(Detector::Javascript::SocketIO::SOCKET_IO_API) &&
        !content.matches?(NODE_SOCKET_SERVER)
    end

    # The events a connection callback registers through a function it hands
    # the socket to: resolve that function (same file, or the module it was
    # imported from), bind its first parameter as the socket and read its
    # body the way a connection callback is read. Followed a few hops deep,
    # each definition once per namespace.
    private def follow_delegations(delegations : Array(Delegation))
      visited = Set(Tuple(String, Int32, String)).new
      seen = Set(String).new
      consts = Hash(String, FileConsts).new
      MAX_DELEGATION_DEPTH.times do
        break if delegations.empty?
        next_round = [] of Delegation
        delegations.uniq.each do |caller_path, callee, namespace|
          isolating_file_errors(caller_path) do
            handler = Noir::JSHandlerResolver.resolve(callee, read_file_content(caller_path), caller_path) || next
            def_path = handler.path || next
            def_line = handler.line || next
            next unless visited.add?({def_path, def_line, namespace})
            scan_delegate(def_path, def_line, namespace, seen, next_round, consts)
          end
        end
        delegations = next_round
      end
    end

    private def scan_delegate(path : String, line : Int32, namespace : String, seen : Set(String), delegations : Array(Delegation), consts : Hash(String, FileConsts))
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
      at = offset
      body.each_line(chomp: false).with_index do |text, index|
        each_event(text, at, -> { consts[path] ||= FileConsts.new(content) }) do |recv, event|
          next unless recv == socket
          url = build_url(namespace, event)
          next unless seen.add?("#{path}\0#{url}")
          @result << build_endpoint(url, path, first_line + index)
        end
        collect_delegations(text, Set{socket}, path, namespace, delegations)
        at += text.bytesize
      end
    end

    # Each non-reserved `{receiver, event}` registered on `line`, which
    # starts at byte `at` of its file. A prefixed name takes the value of
    # the string constant the prefix names at that point; when it names
    # none, or a variable assigned again, the event is kept with the prefix
    # as a `{placeholder}` rather than given a guessed name.
    private def each_event(line : String, at : Int32, consts : -> FileConsts, &)
      line.scan(EVENT_HANDLER) do |em|
        event = em[3]
        if prefix = em[2]?
          value = consts.call.value(prefix, at + em.byte_begin(2))
          event = (value || "{#{prefix}}") + event
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
      consts = nil.as(FileConsts?)
      file_consts = -> { consts ||= FileConsts.new(content); consts.as(FileConsts) }
      at = 0

      content.each_line(chomp: false).with_index do |line, index|
        line_no = index + 1
        line_at = at
        at += line.bytesize

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
        each_event(line, line_at, file_consts) do |recv, event|
          next unless socket_vars.includes?(recv)
          url = build_url(current_ns, event)
          next unless seen.add?(url)
          @result << build_endpoint(url, path, line_no)
        end
        collect_delegations(line, socket_vars, path, current_ns, delegations)
      end
    end

    # The string constants of one file and the block each is declared in.
    # A use sees the innermost declaration whose block holds it; a `let` or
    # `var` assigned again anywhere in the file is not a constant. Built once
    # per file, in one pass.
    class FileConsts
      record Decl, value : String, open : Int32, close : Int32, fixed : Bool

      @decls = Hash(String, Array(Decl)).new

      def initialize(content : String)
        found = [] of Tuple(Int32, String, String, String)
        content.scan(STRING_CONST) { |m| found << {m.byte_begin(0), m[1], m[2], m[3]} }
        return if found.empty?
        opens = block_opens(content, found.map(&.[0]))
        closes = block_closes(content)
        found.each_with_index do |(_, keyword, name, value), i|
          open = opens[i]
          close = open < 0 ? content.bytesize : (closes[open]? || content.bytesize)
          fixed = keyword == "const" || content.scan(/(?<![\w$.])#{Regex.escape(name)}\s*[-+]?=(?![=>])/).size <= 1
          (@decls[name] ||= [] of Decl) << Decl.new(value, open, close, fixed)
        end
      end

      # The value `name` has at byte `at`, or nil when no constant there.
      def value(name : String, at : Int32) : String?
        visible = (@decls[name]? || return).select { |d| d.open < at && at < d.close }
        return if visible.empty?
        innermost = visible.max_by(&.open)
        return if visible.count { |d| d.open == innermost.open } > 1
        innermost.value if innermost.fixed
      end

      # For each offset (ascending), the byte of the `{` whose block holds it,
      # or -1 at the top level.
      private def block_opens(content : String, offsets : Array(Int32)) : Array(Int32)
        result = Array(Int32).new(offsets.size, -1)
        stack = [] of Int32
        next_index = 0
        each_brace(content) do |byte, pos|
          while next_index < offsets.size && offsets[next_index] < pos
            result[next_index] = stack.last? || -1
            next_index += 1
          end
          byte == '{'.ord ? stack << pos : stack.pop?
        end
        while next_index < offsets.size
          result[next_index] = stack.last? || -1
          next_index += 1
        end
        result
      end

      private def block_closes(content : String) : Hash(Int32, Int32)
        closes = Hash(Int32, Int32).new
        stack = [] of Int32
        each_brace(content) do |byte, pos|
          if byte == '{'.ord
            stack << pos
          elsif open = stack.pop?
            closes[open] = pos
          end
        end
        closes
      end

      # Each `{` / `}` outside a string literal.
      private def each_brace(content : String, &)
        bytes = content.to_slice
        quote = 0_u8
        i = 0
        while i < bytes.size
          b = bytes[i]
          if quote != 0
            if b == '\\'.ord
              i += 1
            elsif b == quote
              quote = 0_u8
            end
          elsif b == '"'.ord || b == '\''.ord || b == '`'.ord
            quote = b
          elsif b == '{'.ord || b == '}'.ord
            yield b, i
          end
          i += 1
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
