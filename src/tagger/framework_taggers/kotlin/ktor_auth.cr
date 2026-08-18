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
  ]

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

    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def pre_scan_auth_blocks
    @auth_scopes.clear

    files = collect_files_by_extension(".kt")
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      next unless content.includes?("authenticate")

      scan_auth_blocks(File.expand_path(file), content)
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
      if !route_frames.empty? && AUTHENTICATE_BLOCK_PATTERNS.any? { |pattern, _desc| stripped.matches?(pattern) }
        auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
        auth_name = auth_match ? auth_match[1] : "default"
        auth_frames << {
          threshold:   depth,
          start_line:  line_num,
          prefix:      normalize_prefix(route_frames.map(&.[:prefix])),
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

  private def normalize_prefix(segments : Array(String)) : String
    joined = segments.join("")
    parts = joined.split("/").reject(&.empty?)
    parts.empty? ? "/" : "/" + parts.join("/")
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
        if stripped.matches?(pattern) && brace_depth <= 0
          auth_match = stripped.match(/authenticate\s*\(\s*"([^"]+)"/)
          if auth_match
            return "Ktor authenticate(\"#{auth_match[1]}\") block"
          end
          return "Ktor authenticate block"
        end
      end

      brace_depth += current.count('}') - current.count('{')

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

    while idx <= end_idx
      current = lines[idx]
      stripped = current.strip

      # The next route declaration ends this handler no matter what the
      # braces looked like.
      break if idx > route_line && stripped.matches?(ROUTE_HANDLER)

      ROUTE_AUTH_PATTERNS.each do |pattern, desc|
        return desc if stripped.matches?(pattern)
      end

      brace_depth += current.count('{') - current.count('}')
      entered = true if current.includes?('{')
      break if entered && brace_depth <= 0

      idx += 1
    end

    nil
  end

  # An `authenticate {}` block found by the pre-scan guards this endpoint when
  # the route is declared inside the block's braces. For a route declared in
  # another file — Ktor's `route("/admin") { adminRoutes() }` extension-function
  # split — the braces say nothing, so fall back to the block's `route()`
  # prefix, matched on a segment boundary.
  private def check_scope_auth(endpoint : Endpoint) : String?
    return if @auth_scopes.empty?

    url = endpoint.url
    locations = endpoint.details.code_paths.map { |info| {File.expand_path(info.path), info.line} }

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
