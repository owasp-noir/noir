require "../../../miniparsers/kotlin_source_mask"
require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "ktor_auth", name: "Ktor Auth Tagger", desc: "Identifies Ktor authentication patterns (authenticate blocks, principals)", order: 200)]
class KtorAuthTagger < FrameworkTagger
  # Ktor authenticate block patterns
  AUTHENTICATE_BLOCK_PATTERNS = [
    {/authenticate\s*\(/, "Ktor authenticate block"},
    {/authenticate\s*\(\s*"([^"]+)"/, "Ktor named authenticate"},
    # The default provider: `authenticate { ... }`
    {/^authenticate\s*\{/, "Ktor authenticate block"},
  ]

  # `authenticate("session", optional = true) { ... }` lets an anonymous
  # caller through; it only resolves a principal when credentials are sent.
  # `strategy = AuthenticationStrategy.Optional` (Ktor 3) is the same.
  OPTIONAL_AUTHENTICATE = /\boptional\s*=\s*true\b|\bAuthenticationStrategy\.Optional\b/

  # Ktor session/JWT/basic auth in route context
  ROUTE_AUTH_PATTERNS = [
    {/principal</, "Ktor principal extraction"},
    {/call\.principal/, "Ktor call.principal"},
    {/call\.authentication/, "Ktor call.authentication"},
    {/sessions\.get</, "Ktor session check"},
  ]

  # `route("/api") {` — a nested URL-prefix block.
  ROUTE_BLOCK = /route\s*\(\s*"([^"]+)"/

  # The start of a route handler (`get("/x") {`, `post {`). Used as a
  # boundary so a handler-body scan stops before the next route.
  ROUTE_HANDLER = /^(?:get|post|put|patch|delete|head|options)\s*[({]/

  # One `authenticate {}` block found by the pre-scan: which file it is in,
  # and the line range its braces span.
  alias AuthScope = NamedTuple(file: String, start_line: Int32, end_line: Int32, description: String)

  def initialize(options : Hash(String, YAML::Any))
    super
    @auth_scopes = [] of AuthScope
    @helpers = Hash({String, String}, Symbol).new
    @error_statuses = Hash(String, Set(String)).new
    @status_packages = Hash(String, Set(String)).new
  end

  def self.target_techs : Array(String)
    ["kotlin_ktor"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan for authenticate {} blocks with route prefixes
    pre_scan_auth_blocks
    pre_scan_credential_helpers

    super
  end

  private def pre_scan_auth_blocks
    @auth_scopes.clear

    files = collect_files_by_extension(".kt")
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      next unless content.includes?("authenticate")

      scan_auth_blocks(Noir::PathScope.expand(file), content)
    end
  end

  # Record every `authenticate {}` block nested in a `route()` block in
  # `content`, with the line range it covers.
  #
  # Both stacks are keyed on real brace depth. Popping a `route()` prefix on
  # "any line that is just `}`" — what this used to do — retired the prefix
  # when a `get {}` handler closed, so a block nested two `route()` levels
  # deep was recorded one level up and its tag spilled onto sibling routes,
  # and onto other files entirely. `GoRouteGroupScope#each_group_scoped_line`
  # tracks the same thing the same way.
  private def scan_auth_blocks(file : String, content : String)
    route_frames = [] of Int32
    auth_frames = [] of NamedTuple(threshold: Int32, start_line: Int32, description: String)
    depth = 0

    content.split("\n").each_with_index do |line, idx|
      line_num = idx + 1
      stripped = line.strip

      route_frames << depth if stripped.matches?(ROUTE_BLOCK)

      if !route_frames.empty? && AUTHENTICATE_BLOCK_PATTERNS.any? { |pattern, _desc| stripped.matches?(pattern) } &&
         !stripped.matches?(OPTIONAL_AUTHENTICATE)
        auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
        auth_name = auth_match ? auth_match[1] : "default"
        auth_frames << {
          threshold:   depth,
          start_line:  line_num,
          description: "Protected by Ktor authenticate(\"#{auth_name}\") block",
        }
      end

      depth += line.count('{') - line.count('}')

      while !route_frames.empty? && depth <= route_frames.last
        route_frames.pop
      end
      while !auth_frames.empty? && depth <= auth_frames.last[:threshold]
        close_auth_frame(file, auth_frames.pop, line_num)
      end
    end

    # A block whose brace never closed (truncated or unparseable file) runs
    # to the end of the file.
    while frame = auth_frames.pop?
      close_auth_frame(file, frame, Int32::MAX)
    end
  end

  private def close_auth_frame(file : String,
                               frame : NamedTuple(threshold: Int32, start_line: Int32, description: String),
                               end_line : Int32)
    @auth_scopes << {
      file:        file,
      start_line:  frame[:start_line],
      end_line:    end_line,
      description: frame[:description],
    }
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      # Check for authenticate block wrapping this route
      description = check_enclosing_authenticate(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ktor_auth"))
        return
      end

      # Check route handler body for principal/session access
      description = check_route_auth(lines, line_idx, path_info.path)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "ktor_auth"))
        return
      end
    end

    # Check scope-level auth
    description = check_scope_auth(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "ktor_auth"))
    end
  end

  private def check_enclosing_authenticate(lines : Array(String), route_line : Int32) : String?
    # Walk backwards to find an enclosing authenticate {} block
    # 30-line window: Ktor authenticate blocks can wrap multiple route definitions
    idx = route_line - 1
    brace_depth = 0

    while idx >= 0 && idx >= route_line - 30
      current = lines[idx]
      stripped = current.strip

      # Check pattern BEFORE counting braces on this line
      # brace_depth <= 0 means we haven't left the enclosing scope (handles nested route blocks)
      AUTHENTICATE_BLOCK_PATTERNS.each do |pattern, _desc|
        if stripped.matches?(pattern) && brace_depth <= 0 && !stripped.matches?(OPTIONAL_AUTHENTICATE)
          auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
          if auth_match
            return "Ktor authenticate(\"#{auth_match[1]}\") block"
          end
          return "Ktor authenticate block"
        end
      end

      brace_depth += current.count('}') - current.count('{')
      # Below zero means this line opened a block enclosing the route (a
      # `route("/x") {`, an optional authenticate): the walk is now in that
      # block's parent scope. Without the reset the debt cancelled the next
      # closed sibling block's `}`, and a sibling `authenticate {}` above it
      # looked like it enclosed the route.
      brace_depth = 0 if brace_depth < 0

      idx -= 1
    end

    nil
  end

  # Scan the route's own handler body — and only it — for principal/session
  # access.
  #
  # This used to start one line *below* the route with `brace_depth = 1`,
  # assuming the handler's `{` was still open. For `get("/public") { … }`,
  # closed on its own line, that assumption is false and the walk marched
  # straight into the next route's body: a public route inherited its
  # neighbour's `call.principal<…>()`. Seed the depth from the route line
  # instead, and scan that line too so a one-line handler is read at all.
  private def check_route_auth(lines : Array(String), route_line : Int32, file : String) : String?
    idx = route_line
    end_idx = [route_line + 15, lines.size - 1].min
    brace_depth = 0
    entered = false
    saw_session = false
    handler = [] of String

    while idx <= end_idx
      current = lines[idx]
      stripped = current.strip

      # The next route declaration ends this handler no matter what the
      # braces looked like.
      break if idx > route_line && stripped.matches?(ROUTE_HANDLER)

      visible = Noir::CComments.strip(stripped).strip
      saw_session = true if visible.matches?(/sessions\.get</)
      ROUTE_AUTH_PATTERNS.each do |pattern, desc|
        next if desc == "Ktor session check"
        return desc if stripped.matches?(pattern)
      end

      handler << current
      brace_depth += current.count('{') - current.count('}')
      entered = true if current.includes?('{')
      break if entered && brace_depth <= 0

      idx += 1
    end

    text = Noir::CComments.strip(handler.join("\n"))
    return "Ktor session check" if saw_session && session_missing_refuses?(text)
    credential_helper_guard(handler.join("\n"), file)
  end

  # A project helper the handler calls as a statement of its own is its
  # guard when the helper's definition refuses a missing principal, in one
  # of two exact shapes at the top level of its body:
  #
  #   principal<User>() ?: throw Unauthorized()
  #   val p = principal<User>()
  #   if (p == null) throw Unauthorized()                // or p?.token != secret
  #
  # Only a `throw` stops the handler: a helper that merely responds 401
  # returns, and the handler runs on. A helper with a `return` ahead of its
  # refusal (`if (!Config.authEnabled) return`) refuses only under a
  # setting and is not judged. A helper that returns the principal
  # (`: User?`) guards only when the handler refuses its null result right
  # at the call: `call.validatePrincipal(db) ?: throw Unauthorized()` (or
  # `?: return@get call.respond(HttpStatusCode.Unauthorized)`). The helper
  # is an `ApplicationCall.` / `RoutingCall.` extension called as
  # `call.x(...)`, declared in the handler's own Gradle module, at the top
  # level of the handler with no earlier statement that can answer the
  # caller first, other than with an error status. A call under an `if`, in
  # a string or a comment, a refusal that does not test the principal (a
  # feature flag, a rate limit), and a guest-only `!= null` check guard
  # nothing.
  # ponytail: a helper in a sibling Gradle module the handler's module
  # depends on (`project(":auth")`) is not read; that misses a guard, never
  # invents one.
  HELPER_DEFINITION = /\bfun\s+(?:<[^>\n]*>\s*)?(?:ApplicationCall|RoutingCall)\.(\w+)\s*\(/
  PRINCIPAL_READ    = /(?:call\.)?(?:authentication\.)?(?:principal|sessions\.get)\s*<[^<>\n]*>\s*\([^()\n]*\)/
  READ_ONLY         = /\A#{PRINCIPAL_READ.source}\z/
  READ_ELVIS        = /\A(?:(?:val|var)\s+\w+(?:\s*:\s*[^=\n]+)?\s*=\s*)?#{PRINCIPAL_READ.source}\s*\?:(.*)\z/m
  READ_BINDING      = /\A(?:val|var)\s+(\w+)(?:\s*:\s*[^=\n]+)?\s*=\s*#{PRINCIPAL_READ.source}\z/
  # `if (x == null)` or `if (x?.token != secret)`: true when x is missing.
  ABSENCE_TEST    = /\Aif\s*\(\s*(.+?)\s*(?:==\s*null|\?\.\w+\s*!=\s*(?!null\b)[^()\n]+)\s*\)\s*\{?/m
  THROW_REFUSAL   = /\A\s*throw\s+\w*(?:Unauthorized|Forbidden)\w*\s*\(/
  HANDLER_REFUSAL = /\A\s*(?:throw\s+\w*(?:Unauthorized|Forbidden)\w*\s*\(|return(?:@\w+)?\s+(?:call\.)?respond\s*\(\s*(?:HttpStatusCode\.(?:Unauthorized|Forbidden)\b|40[13]\b))/
  RETURN_RESPOND  = /\breturn(?:@\w+)?\b(\s*(?:call\.)?respond\s*\()?/
  RESPOND_CALL    = /\brespond(\w*)\s*\(/
  # Can answer the caller: a `return` or any `respond*(` call.
  ANSWERS = /\breturn\b|\brespond\w*\s*\(/
  # A status that is no success: `HttpStatusCode.<not 1xx-3xx>` or 4xx/5xx.
  # Ktor's 4xx/5xx `HttpStatusCode` companions, `HttpStatusCode(4xx, ...)` and
  # `HttpStatusCode.fromValue(4xx)`.
  ERROR_STATUS          = /HttpStatusCode\s*(?:\.\s*(?:BadRequest|Unauthorized|PaymentRequired|Forbidden|NotFound|MethodNotAllowed|NotAcceptable|ProxyAuthenticationRequired|RequestTimeout|Conflict|Gone|LengthRequired|PreconditionFailed|PayloadTooLarge|RequestURITooLong|UnsupportedMediaType|RequestedRangeNotSatisfiable|ExpectationFailed|UnprocessableEntity|Locked|FailedDependency|TooEarly|UpgradeRequired|TooManyRequests|RequestHeaderFieldTooLarge|InternalServerError|NotImplemented|BadGateway|ServiceUnavailable|GatewayTimeout|VersionNotSupported|VariantAlsoNegotiates|InsufficientStorage)\b|\(\s*[45]\d\d\b|\.\s*fromValue\s*\(\s*[45]\d\d\s*\))/
  ERROR_STATUS_ARGUMENT = /\A#{ERROR_STATUS.source}/
  # A top-level constant (not one nested in an object or class).
  ERROR_STATUS_CONSTANT = /^(?:(?:private|internal|public)\s+)?(?:const\s+)?val\s+(\w+)\s*(?::\s*HttpStatusCode\s*)?=\s*#{ERROR_STATUS.source}/m
  LOCAL_BINDING         = /\A(?:val|var)\s+(\w+)(?:\s*:\s*[^=\n]+)?\s*=\s*(.+)\z/m
  PACKAGE_LINE          = /^\s*package\s+([\w.]+)/m
  IMPORT_LINE           = /^\s*import\s+([\w.]+)(\.\*)?/m
  HANDLER_CALL          = /\A(?:(?:val|var)\s+\w+(?:\s*:\s*[^=\n]+)?\s*=\s*)?call\.(\w+)\s*\(/
  GRADLE_MODULE         = /\A(?:build\.gradle(?:\.kts)?|pom\.xml)\z/

  private def pre_scan_credential_helpers
    @helpers.clear
    @error_statuses.clear
    @status_packages.clear
    collect_files_by_extension(".kt").each do |file|
      content = read_file(file)
      next if content.nil?
      reads = content.includes?("principal") || content.includes?("sessions.get")
      statuses = content.includes?("HttpStatusCode")
      next unless reads || statuses

      masked = Noir::KotlinSourceMask.visible(content)
      if statuses
        constants = Set(String).new
        masked.scan(ERROR_STATUS_CONSTANT) { |match| constants << match[1] }
        unless constants.empty?
          @error_statuses[Noir::PathScope.expand(file)] = constants
          (@status_packages[kotlin_package(masked)] ||= Set(String).new).concat(constants)
        end
      end
      next unless reads

      module_root = gradle_module(file)
      masked.scan(HELPER_DEFINITION) do |match|
        next unless definition = helper_definition(masked, match.end)
        return_type, body = definition
        if refuses_missing_principal?(body)
          @helpers[{module_root, match[1]}] = :refuses
        elsif return_type.rstrip.ends_with?('?') && body.matches?(PRINCIPAL_READ)
          @helpers[{module_root, match[1]}] ||= :principal
        end
      end
    end
  end

  private def gradle_module(path : String) : String
    nearest_project_root(path, GRADLE_MODULE) || ""
  end

  private def refuses_missing_principal?(body : String) : Bool
    bound = Set(String).new
    top_level_statements(body).each do |statement|
      if elvis = statement.match(READ_ELVIS)
        return true if elvis[1].matches?(THROW_REFUSAL)
      elsif binding = statement.match(READ_BINDING)
        bound << binding[1]
      elsif (test = statement.match(ABSENCE_TEST)) && (bound.includes?(test[1]) || test[1].matches?(READ_ONLY))
        return true if statement[test.end..].matches?(THROW_REFUSAL)
      end
      # Anything able to leave first makes the refusal conditional.
      return false if statement.matches?(/\breturn\b/)
    end
    false
  end

  # The return type text and the body of the function whose parameter list
  # opens just before `from`; a one-line `= expr` body is that expression.
  private def helper_definition(text : String, from : Int32) : {String, String}?
    return unless close = matching_close(text, from - 1)
    idx = close + 1
    while idx < text.size && !{'{', '=', '\n'}.includes?(text[idx])
      idx += 1
    end
    return if idx >= text.size || text[idx] == '\n'
    return_type = text[(close + 1)...idx]
    return {return_type, text[(idx + 1)...(text.index('\n', idx) || text.size)]} if text[idx] == '='
    return unless body_close = matching_close(text, idx)
    {return_type, text[(idx + 1)...body_close]}
  end

  # Index of the bracket closing the one at `open`, or nil.
  private def matching_close(text : String, open : Int32) : Int32?
    depth = 0
    idx = open
    while idx < text.size
      case text[idx]
      when '(', '{', '[' then depth += 1
      when ')', '}', ']'
        depth -= 1
        return idx if depth == 0
      end
      idx += 1
    end
    nil
  end

  # Statements at the top level of `text` (a body without its braces), split
  # on newlines and `;`; a line opening with `?:` or `.` continues the one
  # before it.
  private def top_level_statements(text : String) : Array(String)
    pieces = [] of String
    current = String::Builder.new
    depth = 0
    text.each_char do |char|
      case char
      when '(', '{', '[' then depth += 1
      when ')', '}', ']' then depth -= 1
      end
      if depth <= 0 && (char == '\n' || char == ';')
        pieces << current.to_s
        current = String::Builder.new
      else
        current << char
      end
    end
    pieces << current.to_s

    statements = [] of String
    pieces.each do |piece|
      stripped = piece.strip
      next if stripped.empty?
      if !statements.empty? && (stripped.starts_with?("?:") || stripped.starts_with?('.'))
        statements[-1] = "#{statements[-1]} #{stripped}"
      else
        statements << stripped
      end
    end
    statements
  end

  private def credential_helper_guard(handler : String, file : String) : String?
    return if @helpers.empty?

    masked = Noir::KotlinSourceMask.visible(handler)
    return unless open = masked.index('{')
    body = (close = matching_close(masked, open)) ? masked[(open + 1)...close] : masked[(open + 1)..]
    module_root = gradle_module(file)
    locals = Hash(String, Bool).new
    top_level_statements(body).each do |statement|
      if call = statement.match(HANDLER_CALL)
        case @helpers[{module_root, call[1]}]?
        when :refuses
          return "Ktor #{call[1]}() check"
        when :principal
          if (args_close = matching_close(statement, call.end - 1)) &&
             (elvis = statement[(args_close + 1)..].match(/\A\s*\?:(.*)\z/m)) && elvis[1].matches?(HANDLER_REFUSAL)
            return "Ktor #{call[1]}() check"
          end
        end
      end
      # A statement that can answer the caller before the guard, other than
      # with an error status, leaves the guard behind it.
      return if answers_before_guard?(statement, file, locals)
      if binding = statement.match(LOCAL_BINDING)
        locals[binding[1]] = binding[2].strip.matches?(ERROR_STATUS_ARGUMENT)
      end
    end
    nil
  end

  # True when `statement` can return or respond with something other than
  # an error status: `return@get call.respondText("preview")`, a bare
  # `return@get`, `call.respond(data)`. `return@post call.respond(FORBIDDEN)`
  # with a project `val FORBIDDEN = HttpStatusCode(403, ...)` cannot.
  private def answers_before_guard?(statement : String, file : String, locals : Hash(String, Bool)) : Bool
    return false unless statement.matches?(ANSWERS)
    statement.scan(RETURN_RESPOND) do |found|
      return true unless found[1]?
    end
    statement.scan(RESPOND_CALL) do |found|
      return true unless found[1].empty?
      return true unless (open = found.end - 1) && (close = matching_close(statement, open))
      argument = statement[(open + 1)...close].strip
      return true unless argument.matches?(ERROR_STATUS_ARGUMENT) || error_status_name?(argument, file, locals)
    end
    false
  end

  # Whether the name `argument` is bound to an error status where the
  # handler reads it: a `val` of its own body first, else a top-level
  # constant of the handler's file, of its package, or of a package it
  # imports the name (or `*`) from.
  private def error_status_name?(argument : String, file : String, locals : Hash(String, Bool)) : Bool
    return false unless argument.matches?(/\A\w+\z/)
    return locals[argument] if locals.has_key?(argument)
    return true if @error_statuses[Noir::PathScope.expand(file)]?.try(&.includes?(argument))

    package, imports = file_scope(file)
    return true if @status_packages[package]?.try(&.includes?(argument))
    imports.any? do |path, wildcard|
      owner = wildcard ? path : path.rpartition('.')[0]
      (wildcard || path.ends_with?(".#{argument}")) && !!@status_packages[owner]?.try(&.includes?(argument))
    end
  end

  @file_scopes = Hash(String, {String, Array({String, Bool})}).new

  private def file_scope(file : String) : {String, Array({String, Bool})}
    @file_scopes[file] ||= begin
      content = Noir::KotlinSourceMask.visible(read_file(file) || "")
      imports = [] of {String, Bool}
      content.scan(IMPORT_LINE) { |match| imports << {match[1], !match[2]?.nil?} }
      {kotlin_package(content), imports}
    end
  end

  private def kotlin_package(content : String) : String
    content.match(PACKAGE_LINE).try(&.[1]) || ""
  end

  # `sessions.get` guards only when a missing session refuses or redirects.
  # An optional read that still renders the page does not.
  SESSION_ELVIS   = /sessions\.get\s*<[^>\n]*>\s*\(\s*\)\s*\?:([^\n]*)/
  SESSION_BIND    = /(?:val|var)\s+([A-Za-z_]\w*)\s*=\s*[^\n]*sessions\.get\s*</
  NULL_SESSION    = /if\s*\(\s*[^\n]*sessions\.get\s*<[^>\n]*>\s*\(\s*\)\s*==\s*null\s*\)/
  SESSION_REFUSAL = /respondRedirect\s*\(|HttpStatusCode\.(?:Unauthorized|Forbidden)|\brespond\s*\(\s*(?:HttpStatusCode\.(?:Unauthorized|Forbidden)|40[13]\b)|\bthrow\s+[^\n]*(?:Unauthorized|Forbidden)/

  private def session_missing_refuses?(text : String) : Bool
    if tail = text.match(SESSION_ELVIS)
      return true if session_refusal?(tail[1])
    end

    if bind = text.match(SESSION_BIND)
      name = Regex.escape(bind[1])
      rest = text[bind.end..]
      if tail = rest.match(Regex.new("\\b#{name}\\b\\s*\\?:([^\\n]*)"))
        return true if session_refusal?(tail[1])
      end
      if cond = rest.match(Regex.new("\\bif\\s*\\(\\s*#{name}\\s*==\\s*null\\s*\\)"))
        return true if session_refusal?(read_branch(rest[cond.end..])[0])
      end
      if cond = rest.match(Regex.new("\\bif\\s*\\(\\s*#{name}\\s*!=\\s*null\\s*\\)"))
        if other = else_branch(rest[cond.end..])
          return true if session_refusal?(other)
        end
      end
    end

    if cond = text.match(NULL_SESSION)
      return true if session_refusal?(read_branch(text[cond.end..])[0])
    end
    false
  end

  private def session_refusal?(text : String) : Bool
    text.match(SESSION_REFUSAL) != nil
  end

  # The branch after an `if (...)`, and how many chars it consumed.
  private def read_branch(text : String) : {String, Int32}
    chars = text.chars
    idx = 0
    while idx < chars.size && chars[idx].whitespace?
      idx += 1
    end
    if idx < chars.size && chars[idx] == '{'
      depth = 0
      start = idx + 1
      while idx < chars.size
        char = chars[idx]
        if char == '"'
          idx = skip_kotlin_string(chars, idx)
          next
        end
        if char == '{'
          depth += 1
        elsif char == '}'
          depth -= 1
          return {chars[start...idx].join, idx + 1} if depth == 0
        end
        idx += 1
      end
      return {chars[start..].join, chars.size}
    end

    start = idx
    while idx < chars.size
      char = chars[idx]
      if char == '"'
        idx = skip_kotlin_string(chars, idx)
        next
      end
      break if char == '\n' || word_at?(chars, idx, "else")
      idx += 1
    end
    {chars[start...idx].join, idx}
  end

  private def else_branch(text : String) : String?
    _, consumed = read_branch(text)
    rest = text.chars[consumed..]
    idx = 0
    while idx < rest.size && rest[idx].whitespace?
      idx += 1
    end
    return unless word_at?(rest, idx, "else")
    read_branch(rest[(idx + 4)..].join)[0]
  end

  private def word_at?(chars : Array(Char), idx : Int32, word : String) : Bool
    return false if idx + word.size > chars.size
    word.each_char_with_index do |char, offset|
      return false unless chars[idx + offset] == char
    end
    nxt = idx + word.size
    return false if nxt < chars.size && (chars[nxt].alphanumeric? || chars[nxt] == '_')
    true
  end

  private def skip_kotlin_string(chars : Array(Char), idx : Int32) : Int32
    if idx + 2 < chars.size && chars[idx + 1] == '"' && chars[idx + 2] == '"'
      idx += 3
      while idx + 2 < chars.size && !(chars[idx] == '"' && chars[idx + 1] == '"' && chars[idx + 2] == '"')
        idx += 1
      end
      return Math.min(idx + 3, chars.size)
    end
    idx += 1
    while idx < chars.size
      if chars[idx] == '\\'
        idx += 2
        next
      end
      return idx + 1 if chars[idx] == '"'
      idx += 1
    end
    chars.size
  end

  # An `authenticate {}` block found by the pre-scan guards this endpoint when
  # the route is declared inside the block's braces. A route declared in a
  # `Route.` extension function mounted inside the block
  # (`authenticate { adminRoutes() }`) is tagged by the Ktor analyzer, which
  # knows where the function is called. The block's `route()` prefix is no
  # stand-in for that: a public sibling mounted under the same prefix
  # (`route("/api") { authenticate { adminRoutes() }; publicRoutes() }`)
  # shares it.
  private def check_scope_auth(endpoint : Endpoint) : String?
    return if @auth_scopes.empty?

    locations = endpoint.details.code_paths.map { |info| {Noir::PathScope.expand(info.path), info.line} }

    @auth_scopes.each do |scope|
      next unless locations.any? { |path, line| path == scope[:file] && !line.nil? && line >= scope[:start_line] && line <= scope[:end_line] }
      return scope[:description]
    end

    nil
  end
end
