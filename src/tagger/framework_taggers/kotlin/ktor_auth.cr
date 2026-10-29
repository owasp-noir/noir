require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"

@[Noir::TaggerFor(key: "ktor_auth", name: "Ktor Auth Tagger", desc: "Identifies Ktor authentication patterns (authenticate blocks, principals)", order: 200)]
class KtorAuthTagger < FrameworkTagger
  include PrefixScope

  # Ktor authenticate block patterns
  AUTHENTICATE_BLOCK_PATTERNS = [
    {/authenticate\s*\(/, "Ktor authenticate block"},
    {/authenticate\s*\(\s*"([^"]+)"/, "Ktor named authenticate"},
    # The default provider: `authenticate { ... }`
    {/^authenticate\s*\{/, "Ktor authenticate block"},
  ]

  # `authenticate("session", optional = true) { ... }` lets an anonymous
  # caller through; it only resolves a principal when credentials are sent.
  OPTIONAL_AUTHENTICATE = /\boptional\s*=\s*true\b/

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
  # the line range its braces span, and the `route()` prefix it sits under.
  alias AuthScope = NamedTuple(file: String, start_line: Int32, end_line: Int32,
    prefix: String, description: String)

  def initialize(options : Hash(String, YAML::Any))
    super
    @auth_scopes = [] of AuthScope
  end

  def self.target_techs : Array(String)
    ["kotlin_ktor"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan for authenticate {} blocks with route prefixes
    pre_scan_auth_blocks

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

  # Record every `authenticate {}` block in `content` with the line range it
  # covers and the `route()` prefix it is nested under.
  #
  # Both stacks are keyed on real brace depth. Popping a `route()` prefix on
  # "any line that is just `}`" — what this used to do — retired the prefix
  # when a `get {}` handler closed, so a block nested two `route()` levels
  # deep was recorded one level up and its tag spilled onto sibling routes,
  # and onto other files entirely. `GoRouteGroupScope#each_group_scoped_line`
  # tracks the same thing the same way.
  private def scan_auth_blocks(file : String, content : String)
    route_frames = [] of NamedTuple(threshold: Int32, prefix: String)
    auth_frames = [] of NamedTuple(threshold: Int32, start_line: Int32, prefix: String, description: String)
    depth = 0

    content.split("\n").each_with_index do |line, idx|
      line_num = idx + 1
      stripped = line.strip

      if route_match = stripped.match(ROUTE_BLOCK)
        route_frames << {threshold: depth, prefix: route_match[1]}
      end

      # Only record a block whose route prefix is known.
      if !route_frames.empty? && AUTHENTICATE_BLOCK_PATTERNS.any? { |pattern, _desc| stripped.matches?(pattern) } &&
         !stripped.matches?(OPTIONAL_AUTHENTICATE)
        auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
        auth_name = auth_match ? auth_match[1] : "default"
        auth_frames << {
          threshold:   depth,
          start_line:  line_num,
          prefix:      join_segments(route_frames.map(&.[:prefix])),
          description: "Protected by Ktor authenticate(\"#{auth_name}\") block",
        }
      end

      depth += line.count('{') - line.count('}')

      while !route_frames.empty? && depth <= route_frames.last[:threshold]
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
                               frame : NamedTuple(threshold: Int32, start_line: Int32, prefix: String, description: String),
                               end_line : Int32)
    @auth_scopes << {
      file:        file,
      start_line:  frame[:start_line],
      end_line:    end_line,
      prefix:      frame[:prefix],
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
      description = check_route_auth(lines, line_idx)
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
  private def check_route_auth(lines : Array(String), route_line : Int32) : String?
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

    return "Ktor session check" if saw_session && session_missing_refuses?(Noir::CComments.strip(handler.join("\n")))
    nil
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
  # the route is declared inside the block's braces. For a route declared in
  # another file — Ktor's `route("/admin") { adminRoutes() }` extension-function
  # split — the braces say nothing, so fall back to the block's `route()`
  # prefix, matched on a segment boundary.
  private def check_scope_auth(endpoint : Endpoint) : String?
    return if @auth_scopes.empty?

    url = endpoint.url
    locations = endpoint.details.code_paths.map { |info| {Noir::PathScope.expand(info.path), info.line} }

    @auth_scopes.each do |scope|
      local = locations.select { |path, _| path == scope[:file] }

      if local.empty?
        next if scope[:prefix] == "/"
        return scope[:description] if prefix_covers?(scope[:prefix], url)
      elsif local.any? { |_, line| !line.nil? && line >= scope[:start_line] && line <= scope[:end_line] }
        return scope[:description]
      end
    end

    nil
  end
end
