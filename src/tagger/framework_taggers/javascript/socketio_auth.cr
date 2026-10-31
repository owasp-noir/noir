require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"

@[Noir::TaggerFor(key: "socketio_auth", name: "Socket.IO Auth Tagger", desc: "Identifies Socket.IO event handlers that first call a check refusing a socket without a session", order: 300)]
class SocketIOAuthTagger < FrameworkTagger
  # A Socket.IO event has no route-level guard: the handler checks the
  # socket itself, usually by handing it to a helper first thing
  # (`socket.on("add", async (m, cb) => { try { checkLogin(socket); …`).
  # The helper counts when its definition throws on a socket that lacks a
  # property (`if (!socket.userID) throw new Error(…)`), directly or through
  # a helper it hands the socket on to. A check under a condition, or one
  # that throws when a property is present, does not.

  # `<receiver>.on(` on the event's own line.
  EVENT_RECEIVER = /\b([A-Za-z_$][\w$]*)\s*\.on\(/
  # A statement that hands a variable to a function as its first argument:
  # `checkLogin(socket);`, `await requireAdmin(socket, id);`.
  CHECK_CALL = /^\s*(?:await\s+)?([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*\(\s*([A-Za-z_$][\w$]*)\s*[,)]/
  TRY_OPEN   = /^\s*try\s*\{\s*$/
  CATCH_OPEN = /^\s*\}\s*(?:catch|finally)\b/
  # How many helper hops to follow (`checkLogin` → `betterAuthCheckLogin`).
  MAX_DEPTH = 3

  @stripped = Hash(String, String).new
  @refusals = Hash(Tuple(String, Int32), Bool).new

  def self.target_techs : Array(String)
    ["js_socketio"]
  end

  private def check_endpoint(endpoint : Endpoint)
    return unless endpoint.protocol == "ws"
    path_info = endpoint.details.code_paths.first? || return
    line = path_info.line || return
    path = path_info.path
    raw = read_file(path) || return
    content = stripped(path, raw)
    own = read_file_lines(path).try(&.[line - 1]?) || return
    socket = own.match(EVENT_RECEIVER).try(&.[1]) || return

    depth = 0
    in_try = false
    Noir::JSRouteExtractor.definition_body(content, line).each_line do |text|
      if depth == 0 || (depth == 1 && in_try)
        if (m = text.match(CHECK_CALL)) && m[2] == socket && refusing?(m[1], raw, path, 0)
          endpoint.add_tag(Tag.new("auth", "Protected by Socket.IO check `#{m[1]}(#{socket})` (throws without a session)", "socketio_auth"))
          return
        end
      end
      in_try = true if depth == 0 && text.matches?(TRY_OPEN)
      in_try = false if text.matches?(CATCH_OPEN)
      depth += text.count('{') - text.count('}')
      in_try = false if depth == 0
    end
  end

  # Whether `callee`, as named in `path`, throws when the socket it is
  # handed lacks a property.
  private def refusing?(callee : String, raw : String, path : String, hops : Int32) : Bool
    return false if hops >= MAX_DEPTH
    handler = Noir::JSHandlerResolver.resolve(callee, raw, path) || return false
    def_path = handler.path || return false
    def_line = handler.line || return false
    key = {def_path, def_line}
    cached = @refusals[key]?
    return cached unless cached.nil?
    @refusals[key] = false # a helper that reaches itself
    @refusals[key] = definition_refuses?(def_path, def_line, hops)
  end

  private def definition_refuses?(path : String, line : Int32, hops : Int32) : Bool
    raw = read_file(path) || return false
    content = stripped(path, raw)
    param = Noir::JSRouteExtractor.definition_params(content, line).try(&.first?).presence || return false
    body = Noir::JSRouteExtractor.definition_body(content, line)
    return false unless body.includes?(param)
    escaped = Regex.escape(param)
    return true if body.matches?(/\bif\s*\(\s*!\s*#{escaped}\s*(?:\??\.\s*[A-Za-z_$][\w$]*\s*)+\)\s*\{?\s*throw\b/)
    body.each_line.any? do |text|
      (m = text.match(CHECK_CALL)) && m[2] == param && refusing?(m[1], raw, path, hops + 1)
    end
  end

  private def stripped(path : String, raw : String) : String
    @stripped[path] ||= Noir::JSRouteExtractor.strip_js_comments(raw)
  end
end
