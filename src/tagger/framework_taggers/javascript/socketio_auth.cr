require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"

@[Noir::TaggerFor(key: "socketio_auth", name: "Socket.IO Auth Tagger", desc: "Identifies Socket.IO event handlers that first call a check refusing a socket without a session", order: 300)]
class SocketIOAuthTagger < FrameworkTagger
  # A Socket.IO event has no route-level guard: the handler checks the
  # socket itself, usually by handing it to a helper first thing
  # (`socket.on("add", async (m, cb) => { try { checkLogin(socket); …`).
  #
  # The helper counts when its definition throws, at its own top level, on
  # a socket that lacks a session property (`if (!socket.userID) throw …`),
  # directly or through a helper it hands the socket on to. The check has
  # to come first: only read-only declarations may run before it, in the
  # handler and in the helper, since anything else (a write, a branch that
  # can answer, a log line) already ran for a caller the check refuses. An
  # early return on a setting (`if (process.env.DISABLE_AUTH) return;`) is
  # passed over and noted: that setting lifts the guard.

  # `<receiver>.on(` on the event's own line.
  EVENT_RECEIVER = /\b([A-Za-z_$][\w$]*)\s*\.on\(/
  # A statement that hands a variable to a function as its first argument:
  # `checkLogin(socket)`, `await requireAdmin(socket, id)`.
  CHECK_CALL = /\A(?:await\s+)?([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*\(\s*([A-Za-z_$][\w$]*)\s*[,)]/
  # A declaration with no `await`: reads, does nothing the caller can see.
  READ_DECLARATION = /\A(?:const|let|var)\s+[^=]+=(?!.*\bawait\b)/
  # `const id = await StatusPage.slugToID(slug)`: an awaited call (group 1
  # its name) whose name is no write.
  AWAIT_DECLARATION = /\A(?:const|let|var)\s+[^=]+=\s*await\s+(?:[A-Za-z_$][\w$]*\s*\.\s*)*([A-Za-z_$][\w$]*)\s*\(/
  WRITE_NAME        = /\A(?:insert|create|update|delete|remove|destroy|save|store|write|set|put|post|send|emit|purge|drop|exec|run|add|push|patch|upsert|apply|commit|clear|reset|kill|start|stop|restart|register|grant|revoke|transfer|pay|charge|import|upload|move|rename|copy|mark|toggle|enable|disable|increment|decrement)/i
  # `log.info("socket", …)`, `console.log(…)`: a log line.
  LOG_CALL = /\A(?:console|log|logger|this\s*\.\s*(?:log|logger))\s*\.\s*(?:log|info|debug|warn|trace|verbose|error|silly)\s*\(/
  # A line continuing the statement above (`.map(…)`, `?.x`, `&& y`).
  CONTINUATION = /\A(?:\??\.|&&|\|\||\?\?|[-+*\/?:])/
  # `callback = deleteChildren`: a plain reassignment, no call.
  PLAIN_ASSIGN = /\A[A-Za-z_$][\w$]*\s*=(?!=)[^()]*\z/
  # `if (…)` / `for (…)` / `while (…)` / `else` whose body is the next statement.
  BRANCH_HEAD = /\A(?:else\s+)?(?:if|for|while)\s*\(/
  # `if (process.env.DISABLE_AUTH) return;`, `if (config.noAuth) { return next(); }`.
  SETTING_RETURN = /\Aif\s*\((.*)\)\s*\{?\s*return\b[^;{}]*;?\s*\}?\z/
  SETTING_READ   = /\bprocess\.env\b|\b(?:settings?|config|Settings|Config)\s*\.|\bgetSetting\s*\(|\bsetting\s*\(/
  # A property that says who the caller is: the one a missing login lacks.
  SESSION_PROPERTY = /\A(?:user\w*|session\w*|auth\w*|token\w*|account\w*|login\w*|logged\w*|isLoggedIn|isAuthenticated|identity|principal|member\w*|uid|jwt|decoded\w*)\z/i
  SETTING_NOTE     = " — a setting can lift it"
  # How many helper hops to follow (`checkLogin` → `betterAuthCheckLogin`).
  MAX_DEPTH = 3

  # Where a refusing check is defined, and whether a setting can lift it.
  record Check, path : String, line : Int32, setting : Bool

  @stripped = Hash(String, String).new
  @line_starts = Hash(String, Array(Int32)).new
  @sites = Hash(Tuple(String, String), Tuple(String, Int32)?).new
  @checks = Hash(Tuple(String, Int32, Int32), Check?).new

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
    body = callback_body(path, content, line) || return
    found = leading_check(body, socket, raw, path, 0) || return
    check, call, setting = found
    note = setting || check.setting ? SETTING_NOTE : ""
    # The check's definition, so `noir reach` on it lists the event.
    endpoint.add_tag(Tag.new("auth", "Protected by Socket.IO check `#{call}(#{socket})` (throws without a session)#{note}", "socketio_auth", check.path, check.line))
  end

  # The body of the callback registered on `line` (`socket.on("e", async
  # (d, cb) => {` or `…, function (d, cb) {`): the block after the last
  # `=>` or `function (…)` on the line.
  private def callback_body(path : String, content : String, line : Int32) : String?
    # Line starts are found once per file: a file of thousands of events
    # walked from its top for each one was quadratic.
    starts = @line_starts[path] ||= begin
      offsets = [0]
      pos = 0
      while nl = content.byte_index('\n', pos)
        offsets << (pos = nl + 1)
      end
      offsets
    end
    line_start = starts[line - 1]? || return
    line_end = content.byte_index('\n', line_start) || content.bytesize
    own = content.byte_slice(line_start, line_end - line_start)
    from = if arrow = own.rindex("=>")
             line_start + own[0, arrow].bytesize + 2
           elsif fn = own.match(/\bfunction\b\s*[\w$]*\s*\(/)
             open = line_start + own[0, fn.end(0) - 1].bytesize
             (Noir::JSLiteralScanner.find_matching_paren_at_byte(content, open) || return) + 1
           else
             return
           end
    brace = content.byte_index('{', from) || return
    return unless content.byte_slice(from, brace - from).strip.empty?
    close = Noir::JSLiteralScanner.find_matching_brace_at_byte(content, brace) || return
    content.byte_slice(brace + 1, close - brace - 1)
  end

  # The first check of `body` that refuses `socket`, with the call as
  # written and whether a setting early return came before it; nil when
  # anything but a read or a setting return runs first.
  private def leading_check(body : String, socket : String, raw : String, path : String, hops : Int32) : Tuple(Check, String, Bool)?
    setting = false
    conditional = false
    statements(body).each do |statement|
      if conditional
        return
      elsif unbraced_branch?(statement)
        conditional = true
      elsif statement.starts_with?("try") && (block = try_block(statement))
        return leading_check(block, socket, raw, path, hops).try { |c| {c[0], c[1], c[2] || setting} }
      elsif (m = statement.match(CHECK_CALL)) && m[2] == socket
        check = check_at(m[1], raw, path, hops) || return
        return {check, m[1], setting}
      elsif (s = statement.match(SETTING_RETURN)) && s[1].matches?(SETTING_READ) && !s[1].includes?(socket)
        setting = true
      elsif !lead_read?(statement) && !argument_shuffle?(statement)
        return
      end
    end
    nil
  end

  # `if (typeof deleteChildren === "function") { callback = deleteChildren;
  # deleteChildren = false; }`: a branch that only moves arguments around
  # answers nothing and changes nothing outside the handler.
  private def argument_shuffle?(statement : String) : Bool
    head = statement.match(/\Aif\s*\(/) || return false
    close = Noir::JSLiteralScanner.find_matching_paren(statement, head.end(0) - 1) || return false
    # A call in the condition (`if (db.removeAllSync(d))`) does something.
    return false if statement[head.end(0)...close].includes?('(') || statement[0..close].includes?("await")
    rest = statement[(close + 1)..].strip
    return false unless rest.starts_with?('{') && Noir::JSLiteralScanner.find_matching_brace(rest, 0) == rest.size - 1
    inner = statements(rest[1...-1])
    !inner.empty? && inner.all?(&.matches?(PLAIN_ASSIGN))
  end

  # A branch head with nothing after its condition: the body is the next
  # statement.
  private def unbraced_branch?(statement : String) : Bool
    return true if statement == "else"
    head = statement.match(BRANCH_HEAD) || return false
    close = Noir::JSLiteralScanner.find_matching_paren(statement, head.end(0) - 1) || return true
    statement[(close + 1)..].strip.empty?
  end

  # A statement that only reads or logs, so may run before the check.
  private def lead_read?(statement : String) : Bool
    return true if statement.matches?(READ_DECLARATION) || statement.matches?(LOG_CALL)
    awaited = statement.match(AWAIT_DECLARATION) || return false
    !awaited[1].matches?(WRITE_NAME) && statement.scan(/\bawait\b/).size == 1
  end

  # The top-level statements of a block, split on `;` and line ends; a line
  # that continues the one above (`.filter(Boolean)`) joins it.
  private def statements(body : String) : Array(String)
    rules = Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS
    result = [] of String
    Noir::TopLevelSplit.split(body, ';', rules).each do |part|
      Noir::TopLevelSplit.split(part, '\n', rules).each do |line|
        line = line.strip
        next if line.empty?
        if (last = result.last?) && (line.matches?(CONTINUATION) || last.matches?(/(?:[=(,+\-*\/?:]|&&|\|\|)\z/))
          result[-1] = "#{last}\n#{line}"
        else
          result << line
        end
      end
    end
    result
  end

  # `try { … } catch (e) { throw e; }`: the try block's statements, since
  # the catch hands every throw on.
  private def rethrown_try(statement : String) : String?
    block = try_block(statement) || return
    rest = statement[(statement.index!('{') + block.size + 2)..]
    block if rest.matches?(/\A\s*catch\s*\(\s*([A-Za-z_$][\w$]*)\s*\)\s*\{\s*throw\s+\1\s*;?\s*\}\s*\z/)
  end

  # The inside of the `try { … }` that `statement` opens with.
  private def try_block(statement : String) : String?
    return unless statement.matches?(/\Atry\s*\{/)
    open = statement.index!('{')
    close = Noir::JSLiteralScanner.find_matching_brace(statement, open) || return
    statement[open + 1...close]
  end

  # The definition of `callee`, as named in `path`, when it throws on a
  # socket that lacks a session property; nil otherwise. Cached per hop: a
  # deeper hop has fewer hops left to look.
  private def check_at(callee : String, raw : String, path : String, hops : Int32) : Check?
    return if hops >= MAX_DEPTH
    # Resolved once per name and file: resolving reads the file, and one
    # file can register thousands of events calling the same check.
    site = @sites.fetch({path, callee}) do
      handler = Noir::JSHandlerResolver.resolve(callee, raw, path)
      found = (p = handler.try(&.path)) && (l = handler.try(&.line)) ? {p, l} : nil
      @sites[{path, callee}] = found
    end
    def_path, def_line = site || return
    key = {def_path, def_line, hops}
    return @checks[key] if @checks.has_key?(key)
    @checks[key] = nil # a helper that reaches itself
    @checks[key] = definition_check(def_path, def_line, hops)
  end

  private def definition_check(path : String, line : Int32, hops : Int32) : Check?
    raw = read_file(path) || return
    content = stripped(path, raw)
    param = Noir::JSRouteExtractor.definition_params(content, line).try(&.first?).presence || return
    body = Noir::JSRouteExtractor.definition_body(content, line)
    return unless body.includes?(param)
    refusal = /\Aif\s*\(\s*!\s*#{Regex.escape(param)}\s*((?:\??\.\s*[A-Za-z_$][\w$]*\s*)+)\)\s*\{?\s*throw\b/
    setting = false
    conditional = false
    statements(body).flat_map { |st| rethrown_try(st).try { |b| statements(b) } || [st] }.each do |statement|
      if conditional
        return
      elsif r = statement.match(refusal)
        properties = r[1].split(/\??\./).map(&.strip).reject(&.empty?)
        return unless properties.any?(&.matches?(SESSION_PROPERTY))
        return Check.new(path, line, setting)
      elsif unbraced_branch?(statement)
        conditional = true
      elsif (m = statement.match(CHECK_CALL)) && m[2] == param
        inner = check_at(m[1], raw, path, hops + 1) || return
        return Check.new(path, line, setting || inner.setting)
      elsif (s = statement.match(SETTING_RETURN)) && s[1].matches?(SETTING_READ) && !s[1].includes?(param)
        setting = true
      elsif !lead_read?(statement)
        return
      end
    end
    nil
  end

  private def stripped(path : String, raw : String) : String
    @stripped[path] ||= Noir::JSRouteExtractor.strip_js_comments(raw)
  end
end
