require "../../../models/detector"

module Detector::Javascript
  # Detects a Socket.IO *server*: an `import ... from "socket.io"` /
  # `require("socket.io")` (the server package; the browser client is
  # `socket.io-client`, a different specifier), or a `new Server(` construct
  # paired with a Socket.IO-only API call. Gates the Socket.IO analyzer,
  # which emits inbound `socket.on` events as `ws://` realtime endpoints.
  class SocketIO < Detector
    detector_for "js_socketio"

    SIGNAL = Regex.union(
      /from\s+['"]socket\.io['"]/,
      /require\(\s*['"]socket\.io['"]\s*\)/,
    )

    PACKAGE_MARKER = /"socket\.io"\s*:/
    NEW_SERVER     = /new Server\(/

    # Socket.IO's own server API, required alongside the generic
    # `new Server(` construct below.
    #
    # `new Server(` used to be paired with a bare `.on(`, and neither name
    # belongs to Socket.IO: `ws`, `engine.io`, `@grpc/grpc-js`, `node:http`
    # and `node:net` all export a `Server` class, and `.on(` is in nearly
    # every Node file. A plain `ws` server — `const { Server } =
    # require('ws')` … `socket.on('message', …)` — was therefore detected as
    # Socket.IO, and the Socket.IO analyzer then reported its `socket.on`
    # handlers as realtime `ws://` endpoints that do not exist.
    #
    # Namespaces (`io.of("/admin")`), room targeting (`io.to(room).emit(…)`),
    # `socket.broadcast.emit(…)` and the `io`/`socket` emitters themselves
    # have no counterpart in those libraries — a `ws` socket is written to
    # with `.send(`, and a gRPC or `node:net` server has no emit surface at
    # all. The room argument allows one level of nesting so
    # `io.to(roomFor(id)).emit(…)` still counts.
    SOCKET_IO_API = Regex.union(
      /\.\s*of\s*\(\s*['"`]\//,
      /\.\s*broadcast\s*\.\s*emit\s*\(/,
      /\.\s*to\s*\((?:[^()]|\([^()]*\))*\)\s*\.\s*emit\s*\(/,
      /\b(?:io|socket)\s*\.\s*emit\s*\(/,
    )

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return content_matches?(file_contents, PACKAGE_MARKER)
      end

      return false unless source_file?(filename)
      # Necessary condition for both branches below: the import markers spell
      # `socket.io` and the API branch requires the literal `new Server(`.
      return false unless file_contents.includes?("socket.io") || file_contents.includes?("new Server(")
      return true if content_matches?(file_contents, SIGNAL)
      content_matches?(file_contents, NEW_SERVER) && content_matches?(file_contents, SOCKET_IO_API)
    end

    def applicable?(filename : String) : Bool
      source_file?(filename) || File.basename(filename) == "package.json"
    end

    private def source_file?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
        filename.ends_with?(".cjs") || filename.ends_with?(".jsx") ||
        filename.ends_with?(".ts") || filename.ends_with?(".tsx")
    end
  end
end
