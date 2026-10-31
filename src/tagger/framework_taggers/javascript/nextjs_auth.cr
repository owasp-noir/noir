require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/top_level_split"
require "./js_read_shape"

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
  # A server-side secret: not one the browser is given (`NEXT_PUBLIC_*`,
  # Stripe's `*_PUBLISHABLE_KEY`).
  ENV_SECRET     = /process\.env\.(?!NEXT_PUBLIC_)(?!\w*PUBLISHABLE)\w*(?:KEY|SECRET|TOKEN)\w*/
  SESSION_DENIED = /\bif\s*\(.*(?:!\s*session\b|\bsession\s*(?:\?\.\w+\s*)*(?:===?|!==?)\s*(?:null|undefined)\b|#{ENV_SECRET}\s*!==?|!==?\s*#{ENV_SECRET})/
  # `if (![process.env.CRON_API_KEY, `Bearer ${process.env.CRON_SECRET}`]
  # .includes(apiKey))`: the key is none of the accepted secrets. Read on
  # the line as written, since the template literal holds a secret.
  NEGATED_LIST = /\bif\s*\(.*!\s*\[/
  # `` if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) ``: also read
  # as written, the secret being inside a template literal.
  SECRET_TEMPLATE = /!==?\s*`[^`]*\$\{\s*#{ENV_SECRET}\s*\}[^`]*`|`[^`]*\$\{\s*#{ENV_SECRET}\s*\}[^`]*`\s*!==?/
  # `export const GET = defaultResponderForAppDir(handler)`: group 1 the
  # handler the wrapper is handed.
  WRAPPED_HANDLER = /\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*=\s*[A-Za-z_$][\w$]*\s*\(\s*([A-Za-z_$][\w$]*)\s*\)/
  SECRET_LIST     = /!\s*\[([^\]]*)\]\s*\.\s*includes\s*\(/
  # A statement of the handler that starts with a call:
  # `const user = await authMiddleware();`, `validateRequest(request);`,
  # `return await handler(request);`. Group 1 is the callee.
  HELPER_STATEMENT = /^\s*(?:return\s+|(?:const|let|var)\s+[^=]+=\s*)?(?:await\s+)?([A-Za-z_$][\w$]*)\s*\(/
  CONTROL_WORDS    = Set{"if", "for", "while", "switch", "catch", "function"}
  # `const denied = await checkAuth(); if (denied) return denied;`
  RESULT_NAME = /^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/
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

  # A refusal found in a body: the `if` it sits under, the status, and
  # whether it throws (stopping its caller too) or returns a response (which
  # its caller must hand on).
  record Refusal, condition : String, status : String, throws : Bool

  def self.target_techs : Array(String)
    ["js_nextjs"]
  end

  private def check_endpoint(endpoint : Endpoint)
    target = endpoint.handler || endpoint.details.code_paths.first?
    return unless target && (path = target.path) && (line = target.line)
    return unless (lines = read_file_lines(path)) && line >= 1 && line <= lines.size

    code = function_body(lines, line - 1)
    raw = lines[line - 1, code.size]
    if refusal = session_refusal(code, raw, UNAUTHORIZED)
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js handler check `#{refusal.condition}` (replies #{refusal.status})", "nextjs_auth"))
      return
    end
    if found = helper_refusal(code, raw, path, 0)
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js helper `#{found[0]}()` (#{found[1]})", "nextjs_auth"))
      return
    end

    wrapper = code_only(lines[line - 1]).match(VERB_WRAPPER).try(&.[1])
    if wrapper && (kind = wrapper_refusal(path, wrapper))
      detail = kind == :throw ? "throws unauthorized" : "replies 401"
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js #{wrapper} wrapper (#{detail})", "nextjs_auth"))
      return
    end

    # The handler the wrapper is handed, defined elsewhere (calcom's
    # `import { GET as handler } from "@calcom/features/tasker/api/cron"`).
    if (inner = code_only(lines[line - 1]).match(WRAPPED_HANDLER).try(&.[1])) && (found = wrapped_refusal(path, inner))
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js handler `#{inner}` (#{found})", "nextjs_auth"))
    end
  end

  # How the handler `name`, as named in `path`, refuses an anonymous caller.
  private def wrapped_refusal(path : String, name : String) : String?
    content = read_file(path) || return
    handler = Noir::JSHandlerResolver.resolve(name, content, path) || return
    def_path = handler.path || return
    def_line = handler.line || return
    lines = read_file_lines(def_path) || return
    return unless def_line <= lines.size
    body = function_body(lines, def_line - 1)
    if refusal = session_refusal(body, lines[def_line - 1, body.size], UNAUTHORIZED)
      "replies #{refusal.status}"
    elsif found = helper_refusal(body, lines[def_line - 1, body.size], def_path, 0)
      "through `#{found[0]}()`, #{found[1]}"
    end
  end

  # The session denial sitting above a `mark` hit, or nil. `raw` is `code`
  # as written, line for line.
  private def session_refusal(code : Array(String), raw : Array(String), mark : Regex) : Refusal?
    code.each_with_index do |text, i|
      break if text.matches?(METHOD_BRANCH) && code[i, 3].none?(&.includes?("405"))
      next unless hit = text.match(mark)
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        # A block closed between the `if` and the refusal is not the refusal's.
        break if j < i && code[j].strip == "}"
        next unless code[j].matches?(SESSION_DENIED) || secret_list_denied?(code[j], raw[j]? || "") ||
                    (code[j].matches?(/\bif\s*\(/) && (raw[j]? || "").matches?(SECRET_TEMPLATE))
        throws = code[j..i].any?(&.matches?(/\bthrow\b/))
        return Refusal.new(code[j].strip.rchop('{').strip, hit[1]? || "401", throws)
      end
    end
    nil
  end

  # `![a, b].includes(x)` where every element is a server-side secret: a
  # public literal in the list (`"free"`) makes it a value check, not a key
  # check.
  private def secret_list_denied?(code : String, raw : String) : Bool
    return false unless code.matches?(NEGATED_LIST)
    list = raw.match(SECRET_LIST) || return false
    elements = Noir::TopLevelSplit.split(list[1], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip).reject(&.empty?)
    !elements.empty? && elements.all?(&.matches?(ENV_SECRET))
  end

  # A function the handler calls first thing whose body refuses a caller
  # without a session or secret: `const user = await authMiddleware();`
  # over `if (!session?.user?.id) throw new HttpError({ statusCode: 401 })`.
  # Only the handler's leading statements count: once it has done anything
  # but read (a write, a branch), that already ran for a refused caller. A
  # helper that returns its refusal guards only when the handler hands the
  # result on (`return await f()`, `if (denied) return denied`); one that
  # throws stops the handler wherever its result goes. Returns {name, how}.
  private def helper_refusal(code : Array(String), raw : Array(String), path : String, depth : Int32) : Tuple(String, String, Bool)?
    return if depth >= MAX_HELPER_DEPTH
    content = read_file(path) || return
    level = 0
    code.each_with_index do |text, i|
      # As in `session_refusal`: past a verb branch the call guards only some verbs.
      break if text.matches?(METHOD_BRANCH) && code[i, 3].none?(&.includes?("405"))
      statement = text.strip
      if i > 0 && level == 1 && !statement.empty? && !statement.matches?(/\A[)}\]]/)
        m = text.match(HELPER_STATEMENT)
        if m && !CONTROL_WORDS.includes?(m[1]) && (found = helper_definition_refusal(m[1], content, path, depth))
          return {m[1], found[0], found[1]} if found[1] || propagated?(code, i)
        end
        # Judged as written: `code` has its template literals blanked, and
        # `` sql`DELETE …` `` is a call.
        break unless lead_read?(Noir::CComments.strip(raw[i]? || text, quotes: %("'`)))
      end
      level += text.count('{') - text.count('}')
    end
    nil
  end

  # A leading statement that only reads or logs (`Noir::JSReadShape`):
  # anything else before the check runs for a caller it would refuse.
  private def lead_read?(text : String) : Bool
    Noir::JSReadShape.read_only?(text)
  end

  # Whether the handler hands on what the call at `i` returns.
  private def propagated?(code : Array(String), i : Int32) : Bool
    return true if code[i].matches?(/^\s*return\b/)
    name = code[i].match(RESULT_NAME).try(&.[1]) || return false
    following = code[(i + 1)..].find { |text| !text.strip.empty? } || return false
    escaped = Regex.escape(name)
    following.matches?(/^\s*if\s*\(\s*!?\s*\(?\s*#{escaped}\b[^)]*\)+\s*\{?\s*return\b/)
  end

  @helper_refusals = Hash(Tuple(String, String, Int32), Tuple(String, Bool)?).new

  # How the function `name`, as called in `path`, refuses ("replies 401",
  # "throws unauthorized", or through a helper of its own) and whether the
  # refusal throws. Nil when it does not, or its definition is not in the
  # scan. Keyed by hop: a deeper hop has less depth left to look.
  private def helper_definition_refusal(name : String, content : String, path : String, depth : Int32) : Tuple(String, Bool)?
    key = {path, name, depth}
    return @helper_refusals[key] if @helper_refusals.has_key?(key)
    @helper_refusals[key] = nil # a helper that reaches itself
    handler = Noir::JSHandlerResolver.resolve(name, content, path) || return
    def_path = handler.path || return
    def_line = handler.line || return
    lines = read_file_lines(def_path) || return
    return unless def_line <= lines.size
    body = function_body(lines, def_line - 1)
    raw = lines[def_line - 1, body.size]
    @helper_refusals[key] = if refusal = session_refusal(body, raw, UNAUTHORIZED)
                              {"replies #{refusal.status}", refusal.throws}
                            elsif thrown_unauthorized?(raw, body)
                              {"throws unauthorized", true}
                            elsif found = helper_refusal(body, raw, def_path, depth + 1)
                              {"through `#{found[0]}()`, #{found[1]}", found[2]}
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
    code = raw.map { |line| code_only(line) }
    return :status if session_refusal(code, raw, UNAUTHORIZED)
    :throw if thrown_unauthorized?(raw, code)
  end

  # A throw that says unauthorized (in `raw`, strings kept) under a session
  # denial (in `code`).
  private def thrown_unauthorized?(raw : Array(String), code : Array(String)) : Bool
    raw.each_with_index do |_, i|
      next unless raw[i, 4].join('\n').matches?(THROWN_UNAUTHORIZED)
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        break if j < i && code[j].strip == "}"
        return true if code[j].matches?(SESSION_DENIED) || secret_list_denied?(code[j], raw[j])
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
