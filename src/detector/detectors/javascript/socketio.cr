require "../../../models/detector"

module Detector::Javascript
  # Detects a Socket.IO *server*: an `import ... from "socket.io"` /
  # `require("socket.io")` (the server package; the browser client is
  # `socket.io-client`, a different specifier) or a `new Server(` construct
  # with `.on(` usage. Gates the Socket.IO analyzer, which emits inbound
  # `socket.on` events as `ws://` realtime endpoints.
  class SocketIO < Detector
    SIGNAL = Regex.union(
      /from\s+['"]socket\.io['"]/,
      /require\(\s*['"]socket\.io['"]\s*\)/,
    )

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return file_contents.matches?(/"socket\.io"\s*:/)
      end

      return false unless source_file?(filename)
      return true if file_contents.matches?(SIGNAL)
      file_contents.includes?("new Server(") && file_contents.includes?(".on(")
    end

    def applicable?(filename : String) : Bool
      source_file?(filename) || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_socketio"
    end

    private def source_file?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
        filename.ends_with?(".cjs") || filename.ends_with?(".jsx") ||
        filename.ends_with?(".ts") || filename.ends_with?(".tsx")
    end
  end
end
