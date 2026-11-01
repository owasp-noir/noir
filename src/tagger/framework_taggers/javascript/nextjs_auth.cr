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
  # `const { auth, error } = await parseRequest(request);`
  DESTRUCTURED_RESULT = /^\s*(?:const|let|var)\s+\{([^}]*)\}\s*=/
  # How many helper hops to follow (`GET` → `handler` → `checkCronKey`).
  MAX_HELPER_DEPTH = 2
  # A pages-router handler serves every verb from one body; a 401 after a
  # `req.method` branch guards only some of them. A branch that just
  # refuses other verbs with 405 leaves one verb, so it does not count.
  METHOD_BRANCH = /\b(?:if|switch)\s*\(.*\breq(?:uest)?\.method\b/
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
  # `opt_outs` are the option keys whose truthy value skips it: the refusal
  # sits under `if (!options?.skipAuth)`.
  record Refusal, condition : String, status : String, throws : Bool, opt_outs : Array(String)

  # `return unauthorized()`, `error = () => forbidden()`: a call whose own
  # definition replies 401/403 is that reply. Group 1 the callee.
  REPLY_CALL = /(?:\breturn\s+|=>\s*)(?:await\s+)?([A-Za-z_$][\w$]*)\s*\(/
  # `if (!auth)`: group 1 the value whose absence is refused.
  NEGATED_VALUE = /\bif\s*\(\s*!\s*([A-Za-z_$][\w$]*)(?:\s*\??\.\s*[A-Za-z_$][\w$]*)*\s*\)/
  # The value of a check of the request itself: `auth = await checkAuth(request)`,
  # `const session = await getSession()`. A lookup of submitted credentials
  # (`await authenticate(email, password)`) is a login, not this.
  CALLER_CHECK = /\s*=\s*(?:await\s+)?[\w$.]*(?:[Aa]uth|[Ss]ession)\w*\s*\(\s*(?:\)|req(?:uest)?\b|headers\(\)|cookies\(\))/
  # `!options?.skipAuth`: a negated member test of an option.
  OPT_OUT_TEST = /!\s*[A-Za-z_$][\w$]*\s*\??\.\s*([A-Za-z_$][\w$]*)/

  def self.target_techs : Array(String)
    ["js_nextjs"]
  end

  private def check_endpoint(endpoint : Endpoint)
    target = endpoint.handler || endpoint.details.code_paths.first?
    return unless target && (path = target.path) && (line = target.line)
    return unless (lines = read_file_lines(path)) && line >= 1 && line <= lines.size

    code = function_body(lines, line - 1)
    raw = lines[line - 1, code.size]
    if refusal = session_refusal(code, raw, UNAUTHORIZED, path)
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js handler check `#{refusal.condition}` (replies #{refusal.status})", "nextjs_auth"))
      return
    end
    if found = helper_refusal(code, raw, path, 0)
      # Located at the helper's definition, so `noir reach` on its file finds the route.
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js helper `#{found[0]}()` (#{found[1]})", "nextjs_auth", found[3], found[4]))
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
    if refusal = session_refusal(body, lines[def_line - 1, body.size], UNAUTHORIZED, def_path)
      "replies #{refusal.status}"
    elsif found = helper_refusal(body, lines[def_line - 1, body.size], def_path, 0)
      "through `#{found[0]}()`, #{found[1]}"
    end
  end

  # The session denial sitting above a `mark` hit, or nil. `raw` is `code`
  # as written, line for line.
  private def session_refusal(code : Array(String), raw : Array(String), mark : Regex, path : String? = nil) : Refusal?
    code.each_with_index do |text, i|
      break if text.matches?(METHOD_BRANCH) && code[i, 3].none?(&.includes?("405"))
      status = text.match(mark).try { |hit| hit[1]? || "401" } || reply_helper_status(text, path) || next
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        # A block closed between the `if` and the refusal is not the refusal's.
        break if j < i && code[j].strip == "}"
        next unless code[j].matches?(SESSION_DENIED) || secret_list_denied?(code[j], raw[j]? || "") ||
                    (code[j].matches?(/\bif\s*\(/) && (raw[j]? || "").matches?(SECRET_TEMPLATE)) ||
                    caller_check_absent?(code, j)
        throws = code[j..i].any?(&.matches?(/\bthrow\b/))
        return Refusal.new(code[j].strip.rchop('{').strip, status, throws, opt_out_keys(code, j))
      end
    end
    nil
  end

  # `if (!auth)` where `auth` was set, above it, from a check of the request.
  private def caller_check_absent?(code : Array(String), j : Int32) : Bool
    name = code[j].match(NEGATED_VALUE).try(&.[1]) || return false
    assigned = /\b#{Regex.escape(name)}#{CALLER_CHECK.source}/
    code[0...j].any?(&.matches?(assigned))
  end

  # The option keys of the negated member tests (`!options?.skipAuth`) in the
  # `if`s still open at line `j`.
  private def opt_out_keys(code : Array(String), j : Int32) : Array(String)
    open = [] of {String, Int32}
    depth = 0
    code[0...j].each do |text|
      opens = text.count('{')
      closes = text.count('}')
      open << {text, depth} if opens > closes && text.matches?(/\bif\s*\(/)
      depth += opens - closes
      open.reject! { |entry| entry[1] >= depth }
    end
    open.flat_map { |entry| entry[0].scan(OPT_OUT_TEST).map(&.[1]) }.uniq!
  end

  @reply_helpers = Hash(Tuple(String, String), String?).new

  # The status a reply helper called on `text` answers (`return
  # unauthorized()` over `return Response.json(.., { status: 401 })`).
  private def reply_helper_status(text : String, path : String?) : String?
    return unless path && (name = text.match(REPLY_CALL).try(&.[1]))
    key = {path, name}
    return @reply_helpers[key] if @reply_helpers.has_key?(key)
    @reply_helpers[key] = nil
    content = read_file(path) || return
    handler = Noir::JSHandlerResolver.resolve(name, content, path) || return
    def_path = handler.path || return
    def_line = handler.line || return
    lines = read_file_lines(def_path) || return
    return unless def_line <= lines.size
    # A helper that answers whatever it is handed (`json(data, status)`)
    # names no status of its own.
    @reply_helpers[key] = function_body(lines, def_line - 1).join('\n').match(UNAUTHORIZED).try(&.[1])
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
  private def helper_refusal(code : Array(String), raw : Array(String), path : String, depth : Int32) : Tuple(String, String, Bool, String, Int32)?
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
          # `parseRequest(request, null, { skipAuth: true })` turns it off.
          opted_out = found[2].any? { |key| text.matches?(/\b#{Regex.escape(key)}\s*:\s*true\b/) }
          return {m[1], found[0], found[1], found[3], found[4]} if !opted_out && (found[1] || propagated?(code, i))
        end
        # Judged as written: `code` has its template literals blanked, and
        # `` sql`DELETE …` `` is a call.
        break unless lead_read?(Noir::CComments.strip(raw[i]? || text, quotes: %("'`)), content, path)
      end
      level += text.count('{') - text.count('}')
    end
    nil
  end

  # A leading statement that only reads or logs (`Noir::JSReadShape`):
  # anything else before the check runs for a caller it would refuse.
  private def lead_read?(text : String, content : String, path : String) : Bool
    return true if Noir::JSReadShape.read_only?(text) || text.strip.matches?(ENV_GATE)
    # `const schema = withDateRange({`: a project helper that only builds a
    # validator.
    factory = text.match(SCHEMA_FACTORY_CALL).try(&.[1]) || return false
    schema_factory?(factory, content, path)
  end

  # `if (process.env.CLOUD_MODE) {` / `if (process.env.X !== '1') return notFound();`:
  # a deployment switch that turns the route off for everyone.
  ENV_GATE            = /\Aif\s*\(\s*!?\s*process\.env\.\w+(?:\s*[!=]==?\s*['"`][^'"`]*['"`])?\s*\)\s*(?:\{\z|return\b)/
  SCHEMA_FACTORY_CALL = /\A\s*(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*([A-Za-z_$][\w$]*)\s*\(/
  SCHEMA_RETURN       = /\breturn\s+(?:z|yup|Joi)\b/

  @schema_factories = Hash(Tuple(String, String), Bool).new

  private def schema_factory?(name : String, content : String, path : String) : Bool
    key = {path, name}
    return @schema_factories[key] if @schema_factories.has_key?(key)
    @schema_factories[key] = false
    handler = Noir::JSHandlerResolver.resolve(name, content, path) || return false
    def_path = handler.path || return false
    def_line = handler.line || return false
    lines = read_file_lines(def_path) || return false
    return false unless def_line <= lines.size
    body = function_body(lines, def_line - 1).join('\n')
    @schema_factories[key] = body.matches?(SCHEMA_RETURN) && !body.includes?("await")
  end

  # Whether the handler hands on what the call at `i` returns.
  private def propagated?(code : Array(String), i : Int32) : Bool
    return true if code[i].matches?(/^\s*return\b/)
    names = code[i].match(RESULT_NAME).try { |m| [m[1]] } ||
            code[i].match(DESTRUCTURED_RESULT).try { |m| m[1].split(',').compact_map(&.split(':').last.strip.presence) } ||
            return false
    rest = code[(i + 1)..].reject(&.strip.empty?)
    following = rest.first? || return false
    # `if (error) {` with `return error();` on the next line.
    following = "#{following} #{rest[1]? || ""}" if following.rstrip.ends_with?('{')
    names.any? do |name|
      escaped = Regex.escape(name)
      following.matches?(/^\s*if\s*\(\s*!?\s*\(?\s*#{escaped}\b[^)]*\)+\s*\{?\s*return\b/)
    end
  end

  @helper_refusals = Hash(Tuple(String, String, Int32), Tuple(String, Bool, Array(String), String, Int32)?).new

  # How the function `name`, as called in `path`, refuses ("replies 401",
  # "throws unauthorized", or through a helper of its own) and whether the
  # refusal throws. Nil when it does not, or its definition is not in the
  # scan. Keyed by hop: a deeper hop has less depth left to look.
  private def helper_definition_refusal(name : String, content : String, path : String, depth : Int32) : Tuple(String, Bool, Array(String), String, Int32)?
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
    @helper_refusals[key] = if refusal = session_refusal(body, raw, UNAUTHORIZED, def_path)
                              {"replies #{refusal.status}", refusal.throws, refusal.opt_outs, def_path, def_line}
                            elsif thrown_unauthorized?(raw, body)
                              {"throws unauthorized", true, [] of String, def_path, def_line}
                            elsif found = helper_refusal(body, raw, def_path, depth + 1)
                              {"through `#{found[0]}()`, #{found[1]}", found[2], [] of String, def_path, def_line}
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
    return :status if session_refusal(code, raw, UNAUTHORIZED, def_path)
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
    parens = 0
    opened = false
    previous = ' '
    lines[start..].each do |raw|
      text = code_only(raw)
      body << text
      # Until the body opens, a brace inside the parameter list is a type
      # or a default (`options?: { skipAuth: boolean },` on its own line);
      # one after `=>` opens an arrow body even inside a wrapper's call.
      text.each_char_with_index do |char, idx|
        case char
        when '(' then parens += 1
        when ')' then parens -= 1 if parens > 0
        when '{'
          arrow = previous == '>' && text[0, idx].rstrip.ends_with?("=>")
          if opened || parens == 0 || arrow
            depth += 1
            opened = true
          end
        when '}'
          depth -= 1 if opened || parens == 0
        end
        previous = char unless char.whitespace?
      end
      break if opened ? depth <= 0 : text.rstrip.ends_with?(';')
    end
    body
  end
end
