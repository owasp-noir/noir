require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"

@[Noir::TaggerFor(key: "nextjs_auth", name: "Next.js Auth Tagger", desc: "Identifies Next.js route handlers that reply 401 without a session or shared secret", order: 270)]
class NextjsAuthTagger < FrameworkTagger
  # Next.js has no route-level guard syntax: an API route checks the caller
  # in its own body (`if (!session) return NextResponse.json(.., { status:
  # 401 })`). A 401 reply under a condition on the session, or on a value
  # compared with a `process.env` secret, is that check. A 401 under any
  # other condition (`if (!user)` after a password lookup) is a login
  # failure anonymous callers are meant to reach, so it does not count.
  # 401, or 403 (`{ status: 403 }` for a wrong cron key): both refuse the
  # caller, and SESSION_DENIED decides whether the condition is about them.
  UNAUTHORIZED = /\bstatus(?:Code)?\s*(?::|\()\s*(40[13])\b/
  ENV_SECRET   = /process\.env\.\w*(?:KEY|SECRET|TOKEN)\w*/
  # Also `![process.env.CRON_API_KEY, …].includes(apiKey)`: the key is in
  # none of the accepted secrets.
  SESSION_DENIED = /\bif\s*\(.*(?:!\s*session\b|\bsession\s*(?:\?\.\w+\s*)*(?:===?|!==?)\s*(?:null|undefined)\b|#{ENV_SECRET}\s*!==?|!==?\s*#{ENV_SECRET}|!\s*\[[^\]]*#{ENV_SECRET}[^\]]*\]\s*\.\s*includes\s*\()/
  # A statement of the handler that starts with a call:
  # `const user = await authMiddleware();`, `validateRequest(request);`,
  # `return await handler(request);`. Group 1 is the callee.
  HELPER_STATEMENT = /^\s*(?:return\s+|(?:const|let|var)\s+[^=]+=\s*)?(?:await\s+)?([A-Za-z_$][\w$]*)\s*\(/
  CONTROL_WORDS    = Set{"if", "for", "while", "switch", "catch", "function"}
  # How many helper hops to follow (`GET` → `handler` → `checkCronKey`).
  MAX_HELPER_DEPTH = 2
  # A pages-router handler serves every verb from one body; a 401 after a
  # `req.method` branch guards only some of them. A branch that just
  # refuses other verbs with 405 leaves one verb, so it does not count.
  METHOD_BRANCH = /\breq(?:uest)?\.method\b/
  # How far above the 401 its `if` may sit (a Prettier-wrapped reply).
  CONDITION_LOOKBACK = 6
  # `export const GET = withSession(async ...)`. The wrapper is the guard.
  VERB_WRAPPER = /\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*=\s*([A-Za-z_$][\w$]*)\s*\(/
  # `throw new DubApiError({ code: "unauthorized" })`: the word lives in a
  # string, so this is matched on text that still has strings. The `{` sits
  # between `throw` and the word, and the object may wrap a line or two.
  THROWN_UNAUTHORIZED = /\bthrow\b[\s\S]{0,240}unauthori[sz]ed/i

  def self.target_techs : Array(String)
    ["js_nextjs"]
  end

  private def check_endpoint(endpoint : Endpoint)
    target = endpoint.handler || endpoint.details.code_paths.first?
    return unless target && (path = target.path) && (line = target.line)
    return unless (lines = read_file_lines(path)) && line >= 1 && line <= lines.size

    code = function_body(lines, line - 1)
    if refusal = session_refusal(code, UNAUTHORIZED)
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js handler check `#{refusal[0]}` (replies #{refusal[1]})", "nextjs_auth"))
      return
    end
    if found = helper_refusal(code, path, 0)
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js helper `#{found[0]}()` (#{found[1]})", "nextjs_auth"))
      return
    end

    wrapper = code_only(lines[line - 1]).match(VERB_WRAPPER).try(&.[1])
    if wrapper && (kind = wrapper_refusal(path, wrapper))
      detail = kind == :throw ? "throws unauthorized" : "replies 401"
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js #{wrapper} wrapper (#{detail})", "nextjs_auth"))
    end
  end

  # The `if` line of a session denial sitting above a `mark` hit, and the
  # status the hit replies with, or nil.
  private def session_refusal(code : Array(String), mark : Regex) : Tuple(String, String)?
    code.each_with_index do |text, i|
      break if text.matches?(METHOD_BRANCH) && code[i, 3].none?(&.includes?("405"))
      next unless hit = text.match(mark)
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        # A block closed between the `if` and the refusal is not the refusal's.
        break if j < i && code[j].strip == "}"
        next unless code[j].matches?(SESSION_DENIED)
        return {code[j].strip.rchop('{').strip, hit[1]? || "401"}
      end
    end
    nil
  end

  # A function the handler calls in one of its own top-level statements
  # whose body refuses a caller without a session or secret: `const user =
  # await authMiddleware();` over `if (!session?.user?.id) throw new
  # HttpError({ statusCode: 401 })`. A call nested in a branch is not made
  # for every request, so only the handler's first level counts.
  private def helper_refusal(code : Array(String), path : String, depth : Int32) : Tuple(String, String)?
    return if depth >= MAX_HELPER_DEPTH
    content = read_file(path) || return
    level = 0
    code.each_with_index do |text, i|
      # As in `session_refusal`: past a verb branch the call guards only some verbs.
      break if text.matches?(METHOD_BRANCH) && code[i, 3].none?(&.includes?("405"))
      if i > 0 && level == 1 && (m = text.match(HELPER_STATEMENT)) && !CONTROL_WORDS.includes?(m[1])
        if found = helper_definition_refusal(m[1], content, path, depth)
          return {m[1], found}
        end
      end
      level += text.count('{') - text.count('}')
    end
    nil
  end

  @helper_refusals = Hash(Tuple(String, String), String?).new

  # How the function `name`, as called in `path`, refuses: "replies 401",
  # "throws unauthorized", or through a helper of its own. Nil when it does
  # not, or its definition is not in the scan.
  private def helper_definition_refusal(name : String, content : String, path : String, depth : Int32) : String?
    key = {path, name}
    return @helper_refusals[key] if @helper_refusals.has_key?(key)
    @helper_refusals[key] = nil # a helper that reaches itself
    handler = Noir::JSHandlerResolver.resolve(name, content, path) || return
    def_path = handler.path || return
    def_line = handler.line || return
    lines = read_file_lines(def_path) || return
    return unless def_line <= lines.size
    body = function_body(lines, def_line - 1)
    @helper_refusals[key] = if refusal = session_refusal(body, UNAUTHORIZED)
                              "replies #{refusal[1]}"
                            elsif thrown_unauthorized?(body)
                              "throws unauthorized"
                            elsif found = helper_refusal(body, def_path, depth + 1)
                              "through `#{found[0]}()`, #{found[1]}"
                            end
  end

  # `:status` when the wrapper's body replies 401 under a missing session,
  # `:throw` when it throws an error whose code or name says unauthorized.
  # Nil when the wrapper does not refuse (`withPassthrough`).
  private def wrapper_refusal(path : String, name : String) : Symbol?
    content = read_file(path) || return
    handler = Noir::JSHandlerResolver.resolve(name, content, path) || return
    def_path = handler.path || return
    def_line = handler.line || return
    source = read_file(def_path) || return
    stripped = Noir::JSRouteExtractor.strip_js_comments(source)
    raw = Noir::JSRouteExtractor.definition_body(stripped, def_line).lines
    return :status if session_refusal(raw.map { |line| code_only(line) }, UNAUTHORIZED)
    :throw if thrown_unauthorized?(raw)
  end

  private def thrown_unauthorized?(code : Array(String)) : Bool
    code.each_with_index do |_, i|
      next unless code[i, 4].join('\n').matches?(THROWN_UNAUTHORIZED)
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        break if j < i && code[j].strip == "}"
        return true if code[j].matches?(SESSION_DENIED)
      end
    end
    false
  end

  # The comment-stripped lines from `start` to the brace that closes the
  # first one opened from there, or to the first `;` when a statement (an
  # `import` at a line-1 fallback) ends before any brace opens.
  private def function_body(lines : Array(String), start : Int32) : Array(String)
    body = [] of String
    depth = 0
    opened = false
    lines[start..].each do |raw|
      text = code_only(raw)
      body << text
      depth += text.count('{') - text.count('}')
      opened ||= text.includes?('{')
      break if opened ? depth <= 0 : text.rstrip.ends_with?(';')
    end
    body
  end
end
