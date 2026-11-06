require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/top_level_split"
require "./js_read_shape"
require "./js_option_gate"

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
  # branch on `req.method` that answers some verbs guards only the others.
  # A branch that just refuses other verbs with 405 leaves one verb, and one
  # that answers nothing (`else if (isGet) { query = … }`) splits no verbs.
  VERB_READ = /\breq(?:uest)?\.method\b/
  # `const method = req.method`, `const isGet = request.method === 'GET'`,
  # `const { method } = req`: names the verb is read into.
  METHOD_ALIAS  = /\b(?:const|let|var)\s+(?:([A-Za-z_$][\w$]*)\s*=\s*req(?:uest)?\.method\b|\{[^}]*\bmethod\b[^}]*\}\s*=\s*req(?:uest)?\s*;?\s*\z)/
  BRANCH_HEAD   = /\b(?:if|switch)\s*\(/
  BRANCH_ANSWER = /\breturn\b|\bres\s*\.\s*(?:status|json|send|end|redirect)\b/
  # How far above the 401 its `if` may sit (a Prettier-wrapped reply).
  CONDITION_LOOKBACK = 6
  # `} else if (…) {`, `else {`: a sibling branch of the `if` above it.
  ELSE_BRANCH = /\A\}?\s*else\b/
  # `export const GET = withSession(async ...)`. The wrapper is the guard.
  VERB_WRAPPER = /\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*=\s*([A-Za-z_$][\w$]*)\s*\(/
  # `throw new DubApiError({ code: "unauthorized" })`: the word lives in a
  # string, so this is matched on text that still has strings. The `{` sits
  # between `throw` and the word, and the object may wrap a line or two.
  THROWN_UNAUTHORIZED = /\bthrow\b[\s\S]{0,240}unauthori[sz]ed/i

  # A refusal found in a body: the `if` it sits under, the status, whether
  # it throws (stopping its caller too) or returns a response (which its
  # caller must hand on), the `if`s still open around it, and the name the
  # refusal is stored in (`error = () => unauthorized()`: `error`).
  record Refusal, condition : String, status : String, throws : Bool, enclosing : Array(String), carrier : String?

  # How a helper's definition refuses: `gates` say which calls it refuses
  # (`Noir::JSOptionGate`), `path`/`line` locate the definition.
  record HelperDef, how : String, throws : Bool, gates : Array(Noir::JSOptionGate::Gate), path : String, line : Int32, carrier : String?, note : String?

  # A helper call that refuses the handler's anonymous callers. `note` says
  # what can still open it (an option the call passes, a deployment switch).
  record HelperHit, name : String, how : String, throws : Bool, path : String, line : Int32, note : String?

  # `return unauthorized()`, `throw unauthorized()`, `error = () =>
  # forbidden()`: a call whose own definition replies 401/403 is that reply.
  # Group 1 the callee.
  REPLY_CALL = /(?:\breturn\s+|\bthrow\s+|=>\s*)(?:await\s+)?([A-Za-z_$][\w$]*)\s*\(/
  # `error = () => unauthorized();`: group 1 the name a refusal is stored in.
  CARRIER = /\A\s*(?:(?:let|const|var)\s+)?([A-Za-z_$][\w$]*)\s*=(?![=>])/
  # `if (!auth)`: group 1 the value whose absence is refused.
  NEGATED_VALUE = /\bif\s*\(\s*!\s*([A-Za-z_$][\w$]*)(?:\s*\??\.\s*[A-Za-z_$][\w$]*)*\s*\)/
  # `if (typeof token === "string")`: a check that answers an error message
  # in place of the token (linkwarden's `verifyToken`) is refused the same
  # way. Only `"string"`: `typeof null` is `"object"`, so other type tests
  # let a check that answers null through. Matched on `typed_code`.
  TYPEOF_DENIED = /\bif\s*\(\s*typeof\s+([A-Za-z_$][\w$]*)\s*===?\s*"string"\s*\)/
  # `auth = await checkAuth(request)`, `const session = await getSession()`:
  # group 1 the value, group 2 the callee. Whether the callee checks the
  # caller is judged by its definition (`caller_check_callee?`).
  CALLER_CHECK = /\b([A-Za-z_$][\w$]*)\s*=\s*(?:await\s+)?([\w$.]*(?:[Aa]uth|[Ss]ession)\w*)\s*\(\s*(?:\{\s*)?(?:\)|req(?:uest)?\b|headers\(\)|cookies\(\))/
  # `const token = await verifyToken({ req })`, `getBearerToken(request)`: a
  # token read off the request object itself. A token taken from a field
  # (`findResetToken(req.body.token)`) is one being redeemed, not the caller's.
  TOKEN_CHECK = /\b([A-Za-z_$][\w$]*)\s*=\s*(?:await\s+)?([\w$.]*Token\w*)\s*\(\s*(?:\{\s*)?req(?:uest)?\s*[,})]/
  # Token callees that mint or redeem one rather than check the caller's.
  TOKEN_MINT = /(?:\A|\.)(?:generate|create|issue|sign|consume|find|reset|new|make|send|revoke)[A-Z]/
  # A read of the submitted body. With a password in it, the helper is a login.
  BODY_READ  = /\.\s*(?:json|formData|text)\s*\(|\breq(?:uest)?\s*\.\s*body\b/
  CREDENTIAL = /password|credential/i
  # Starting a session (`cookies().set(...)`, a `Set-Cookie` header) is a login too.
  COOKIE_WRITE = /\bcookies\s*\(\s*\)\s*\.\s*set\s*\(|\.\s*cookies\s*\.\s*set\s*\(|set-cookie/i

  # `if (process.env.CLOUD_MODE) {` / `if (process.env.X !== '1') return notFound();`:
  # a deployment switch. One that refuses everyone may come before the
  # check; any other runs for a caller the check would refuse, when set.
  ENV_GATE            = /\Aif\s*\(\s*!?\s*process\.env\.\w+(?:\s*[!=]==?\s*['"`][^'"`]*['"`])?\s*\)\s*(?:\{\z|return\b)/
  ENV_REFUSAL         = /\b(?:return|throw)\b[\s\S]*(?:\bstatus(?:Code)?\s*(?::|\()\s*4\d\d\b|\b(?:notFound|forbidden|unauthorized|badRequest|methodNotAllowed)\s*\()/
  SCHEMA_FACTORY_CALL = /\A\s*(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*([A-Za-z_$][\w$]*)\s*\(/
  SCHEMA_RETURN       = /\breturn\s+(?:z|yup|Joi)\b/
  OPTION_NOTE         = "an option can make it public"
  SETTING_NOTE        = "a setting can open it"

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
      how = found.note ? "#{found.how}; #{found.note}" : found.how
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js helper `#{found.name}()` (#{how})", "nextjs_auth", found.path, found.line))
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
      "through `#{found.name}()`, #{found.how}"
    end
  end

  # The session denial sitting above a `mark` hit, or nil. `raw` is `code`
  # as written, line for line. The condition is found before a reply
  # helper's definition is looked up, so only a reply under one costs a
  # lookup.
  private def session_refusal(code : Array(String), raw : Array(String), mark : Regex, path : String? = nil) : Refusal?
    verb = verb_matcher(code)
    callers = caller_assignments(code, path)
    code.each_with_index do |text, i|
      break if method_branch?(code, i, verb)
      hit = text.match(mark).try { |m| m[1]? || "401" }
      next unless hit || text.matches?(REPLY_CALL)
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        stripped = code[j].strip
        # A block closed between the `if` and the refusal is not the refusal's.
        break if j < i && stripped == "}"
        if refusal_condition?(code, raw, j, callers)
          # `if (!auth) { log(); }` / `if (!auth) skip();`: closed on its own line.
          break if j < i && (stripped.ends_with?(';') || (stripped.ends_with?('}') && stripped.count('{') <= stripped.count('}')))
          status = hit || reply_helper_status(text, path)
          break unless status
          throws = code[j..i].any?(&.matches?(/\bthrow\b/))
          carrier = code[(j + 1)..i].compact_map(&.match(CARRIER).try(&.[1])).first?
          condition = code[j].includes?("typeof") ? typed_code(raw[j]? || code[j]) : code[j]
          return Refusal.new(condition.strip.rchop('{').strip, status, throws, enclosing_conditions(code, j), carrier)
        end
        # Nor is an `else` branch of one above it.
        break if j < i && stripped.matches?(ELSE_BRANCH)
      end
    end
    nil
  end

  private def refusal_condition?(code : Array(String), raw : Array(String), j : Int32, callers : Hash(String, Int32)) : Bool
    text = code[j]
    return true if text.matches?(SESSION_DENIED) || secret_list_denied?(text, raw[j]? || "")
    return true if text.matches?(/\bif\s*\(/) && (raw[j]? || "").matches?(SECRET_TEMPLATE)
    # `if (!auth)` where `auth` was set, above it, from a check of the request.
    typeof_hit = text.includes?("typeof") ? typed_code(raw[j]? || "").match(TYPEOF_DENIED) : nil
    name = (text.match(NEGATED_VALUE) || typeof_hit).try(&.[1]) || return false
    (at = callers[name]?) ? at < j : false
  end

  # The values set from a check of the caller, each at the first line it is set.
  private def caller_assignments(code : Array(String), path : String?) : Hash(String, Int32)
    found = {} of String => Int32
    code.each_with_index do |text, i|
      next unless text.includes?('=')
      m = text.match(CALLER_CHECK) || text.match(TOKEN_CHECK).try { |t| t unless t[2].matches?(TOKEN_MINT) }
      found[m[1]] ||= i if m && caller_check_callee?(m[2], path)
    end
    found
  end

  # `line` as code, like `code_only`, but keeping a `"string"` literal so a
  # `typeof` test still names its type. A literal holding one (a template
  # quoting `typeof x === "string"`) is emptied whole.
  private def typed_code(line : String) : String
    Noir::CComments.strip(line, quotes: %("'`)).gsub(STRING_LITERAL) { |lit| lit[1...-1] == "string" ? %("string") : %("") }
  end

  @caller_checks = Hash(Tuple(String, String), Bool).new

  # Whether `callee`, named like a caller check, is one: its definition is
  # not a login, reading a password from the body (`authenticateUser(request)`)
  # or starting a session (`createSession(request)`). What a check reads
  # varies (polar's reads a header its middleware sets), so it is not
  # required to name a cookie or token. A callee defined outside the scan
  # (`getServerSession`, `auth.api.getSession`) is a library's.
  private def caller_check_callee?(callee : String, path : String?) : Bool
    return true if path.nil? || callee.includes?('.')
    key = {path, callee}
    return @caller_checks[key] if @caller_checks.has_key?(key)
    @caller_checks[key] = true
    content = read_file(path) || return true
    handler = Noir::JSHandlerResolver.resolve(callee, content, path) || return true
    def_path = handler.path || return true
    def_line = handler.line || return true
    lines = read_file_lines(def_path) || return true
    return true unless def_line <= lines.size
    body = lines[def_line - 1, function_body(lines, def_line - 1).size].join('\n')
    @caller_checks[key] = !((body.matches?(BODY_READ) && body.matches?(CREDENTIAL)) || body.matches?(COOKIE_WRITE))
  end

  # The `if` lines still open at line `j`.
  private def enclosing_conditions(code : Array(String), j : Int32) : Array(String)
    open = [] of {String, Int32}
    depth = 0
    code[0...j].each do |text|
      opens = text.count('{')
      closes = text.count('}')
      open << {text, depth} if opens > closes && text.matches?(/\bif\s*\(/)
      depth += opens - closes
      open.reject! { |entry| entry[1] >= depth }
    end
    open.map(&.[0])
  end

  # What reads the verb in `code`: `req.method`, and the names it is read into.
  private def verb_matcher(code : Array(String)) : Regex
    aliases = code.compact_map { |text| text.match(METHOD_ALIAS).try { |m| m[1]? || "method" } }.uniq!
    return VERB_READ if aliases.empty?
    Regex.new("#{VERB_READ.source}|\\b(?:#{aliases.map { |name| Regex.escape(name) }.join('|')})\\b")
  end

  # An `if`/`switch` at line `i` that branches on the verb and answers some
  # verbs in its block (not with a 405).
  private def method_branch?(code : Array(String), i : Int32, verb : Regex) : Bool
    at = code[i].index(BRANCH_HEAD) || return false
    return false unless code[i, 4].join(' ').matches?(verb)
    block = branch_block(code, i, at)
    condition = block[0, block.index('{') || block.size]
    condition.matches?(verb) && !block.includes?("405") && block.matches?(BRANCH_ANSWER)
  end

  # The text of the statement starting at column `at` of line `i`: to the
  # brace closing the block it opens, or to its `;` when it opens none.
  private def branch_block(code : Array(String), i : Int32, at : Int32) : String
    String.build do |io|
      depth = 0
      opened = false
      code[i, 400].each_with_index do |line, k|
        segment = k == 0 ? line[at..] : line
        io << segment << '\n'
        segment.each_char do |char|
          if char == '{'
            depth += 1
            opened = true
          elsif char == '}'
            depth -= 1
          end
        end
        break if opened ? depth <= 0 : segment.rstrip.ends_with?(';')
      end
    end
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
  # result on (`return await f()`, `if (error) return error()`); one that
  # throws stops the handler wherever its result goes.
  private def helper_refusal(code : Array(String), raw : Array(String), path : String, depth : Int32) : HelperHit?
    return if depth >= MAX_HELPER_DEPTH
    content = read_file(path) || return
    verb = verb_matcher(code)
    notes = [] of String
    level = 0
    code.each_with_index do |text, i|
      # As in `session_refusal`: past a verb branch the call guards only some verbs.
      break if method_branch?(code, i, verb)
      statement = text.strip
      if i > 0 && level == 1 && !statement.empty? && !statement.matches?(/\A[)}\]]/)
        m = text.match(HELPER_STATEMENT)
        if m && !CONTROL_WORDS.includes?(m[1]) && (found = helper_definition_refusal(m[1], content, path, depth))
          args, last = call_args(code, i, m.end(0) - 1)
          # `parseRequest(request, null, { skipAuth: true })` turns it off.
          outcome = Noir::JSOptionGate.outcome(found.gates, args, ->(name : String) { const_value(code, i, name) })
          if outcome != :skipped && (found.throws || propagated?(code, i, last, found.carrier))
            notes << OPTION_NOTE if outcome == :unknown
            found.note.try { |note| notes << note }
            return HelperHit.new(m[1], found.how, found.throws, found.path, found.line, notes.empty? ? nil : notes.uniq.join("; "))
          end
        end
        if statement.matches?(ENV_GATE)
          notes << SETTING_NOTE unless env_refusal?(branch_block(code, i, text.index("if") || 0))
        elsif !lead_read?(Noir::CComments.strip(raw[i]? || text, quotes: %("'`)), content, path)
          # Judged as written: `code` has its template literals blanked, and
          # `` sql`DELETE …` `` is a call.
          break
        end
      end
      level += text.count('{') - text.count('}')
    end
    nil
  end

  # A deployment switch's block that only refuses (`return notFound()`).
  private def env_refusal?(block : String) : Bool
    body = block.sub(/\A[^)]*\)/, "")
    body.matches?(ENV_REFUSAL) && !body.includes?("await")
  end

  # The arguments of the call whose `(` is at column `open` of line `i`, and
  # the line the call ends on.
  private def call_args(code : Array(String), i : Int32, open : Int32) : Tuple(Array(String), Int32)
    joined = code[i, 20].join('\n')
    close = Noir::JSRouteExtractor.find_matching_paren(joined, open) || return {[] of String, i}
    args = Noir::TopLevelSplit.split(joined[(open + 1)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
    {args.reject(&.strip.empty?), i + joined[0...close].count('\n')}
  end

  # The initializer of `const name = …` above line `i`.
  private def const_value(code : Array(String), i : Int32, name : String) : String?
    code[0...i].join('\n').match(/\bconst\s+#{Regex.escape(name)}\s*(?::[^=]+)?=\s*([^;]*)/).try(&.[1])
  end

  # A leading statement that only reads or logs (`Noir::JSReadShape`):
  # anything else before the check runs for a caller it would refuse.
  private def lead_read?(text : String, content : String, path : String) : Bool
    return true if Noir::JSReadShape.read_only?(text)
    # `const schema = withDateRange({`: a project helper that only builds a
    # validator.
    factory = text.match(SCHEMA_FACTORY_CALL).try(&.[1]) || return false
    schema_factory?(factory, content, path)
  end

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

  # Whether the handler hands on what the call at line `i` (ending at line
  # `last`) returns. A destructured result must hand on the name the helper
  # stores its refusal in: `return error()` after `if (error)`, not a
  # validation `error` when the 401 travels in `authError`.
  private def propagated?(code : Array(String), i : Int32, last : Int32, carrier : String?) : Bool
    return true if code[i].matches?(/^\s*return\b/)
    rest = code[(last + 1)..].reject(&.strip.empty?)
    following = rest.first? || return false
    # `if (error) {` with `return error();` on the next line.
    following = "#{following} #{rest[1]? || ""}" if following.rstrip.ends_with?('{')
    if m = code[i].match(RESULT_NAME)
      escaped = Regex.escape(m[1])
      return following.matches?(/^\s*if\s*\(\s*!?\s*\(?\s*#{escaped}\b[^)]*\)+\s*\{?\s*return\b/)
    end
    m = code[i].match(DESTRUCTURED_RESULT) || return false
    m[1].split(',').any? do |entry|
      key = entry.split(':').first.strip.lchop("...").split('=').first.strip
      local = entry.split(':').last.split('=').first.strip
      next false if local.empty? || (carrier && key != carrier)
      escaped = Regex.escape(local)
      following.matches?(/^\s*if\s*\(\s*!?\s*\(?\s*#{escaped}\b[^)]*\)+\s*\{?\s*return\s+(?:await\s+)?#{escaped}\b/)
    end
  end

  @helper_refusals = Hash(Tuple(String, String, Int32), HelperDef?).new

  # How the function `name`, as called in `path`, refuses ("replies 401",
  # "throws unauthorized", or through a helper of its own). Nil when it does
  # not, or its definition is not in the scan. Keyed by hop: a deeper hop
  # has less depth left to look.
  private def helper_definition_refusal(name : String, content : String, path : String, depth : Int32) : HelperDef?
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
    none = [] of Noir::JSOptionGate::Gate
    @helper_refusals[key] = if refusal = session_refusal(body, raw, UNAUTHORIZED, def_path)
                              gates = Noir::JSOptionGate.gates(refusal.enclosing, Noir::JSOptionGate.params(parameter_list(body)))
                              HelperDef.new("replies #{refusal.status}", refusal.throws, gates, def_path, def_line, refusal.carrier, nil)
                            elsif thrown_unauthorized?(raw, body)
                              HelperDef.new("throws unauthorized", true, none, def_path, def_line, nil, nil)
                            elsif found = helper_refusal(body, raw, def_path, depth + 1)
                              HelperDef.new("through `#{found.name}()`, #{found.how}", found.throws, none, def_path, def_line, nil, found.note)
                            end
  end

  # The text between a definition's parameter parentheses.
  private def parameter_list(body : Array(String)) : String
    joined = body.first(20).join('\n')
    open = joined.index('(') || return ""
    close = Noir::JSRouteExtractor.find_matching_paren(joined, open) || return ""
    joined[(open + 1)...close]
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
        stripped = code[j].strip
        break if j < i && stripped == "}"
        return true if code[j].matches?(SESSION_DENIED) || secret_list_denied?(code[j], raw[j])
        break if j < i && stripped.matches?(ELSE_BRANCH)
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
      # one after `=>` or `)` opens a body even inside a wrapper's call
      # (`withSentry(async function handler(req, res) {`).
      text.each_char_with_index do |char, idx|
        case char
        when '(' then parens += 1
        when ')' then parens -= 1 if parens > 0
        when '{'
          arrow = previous == '>' && text[0, idx].rstrip.ends_with?("=>")
          if opened || parens == 0 || arrow || previous == ')'
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
