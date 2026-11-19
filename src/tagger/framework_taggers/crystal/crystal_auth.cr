require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "crystal_auth", name: "Crystal Auth Tagger", desc: "Identifies Crystal framework authentication patterns (Kemal, Amber, Lucky)", order: 240)]
class CrystalAuthTagger < FrameworkTagger
  # Amber auth pipe patterns
  AMBER_AUTH_PATTERNS = [
    {/pipeline\s+:auth/, "Amber :auth pipeline"},
    {/plug\s+Authenticate/, "Amber Authenticate plug"},
    {/plug\s+\w*[Aa]uth\w*/, "Amber auth plug"},
  ]

  # Kemal file-level filters: they guard every route below them.
  KEMAL_FILTER_PATTERNS = [
    {/before_all.*do.*auth/i, "Kemal before_all auth filter"},
    {/basic_auth/, "Kemal basic_auth"},
  ]

  # Kemal checks that guard only the handler making them.
  KEMAL_HANDLER_PATTERNS = [
    {/env\.session\.string\s*\(\s*"user/, "Kemal session user check"},
    {/env\.get\s*\(\s*"auth/, "Kemal auth context"},
  ]

  # Lucky auth patterns
  LUCKY_AUTH_PATTERNS = [
    {/include Auth::RequireSignIn/, "Lucky Auth::RequireSignIn"},
    {/before require_sign_in/, "Lucky require_sign_in before action"},
    # A bare `current_user` reference (e.g. `UserSerializer.new(current_user)`
    # in a handler body) is not sign-in enforcement; it false-positived on
    # any action that merely reads the user. The real signals above
    # (RequireSignIn / require_sign_in) cover Lucky auth.
  ]

  # Lucky's opt-out of the sign-in `BrowserAction` requires: the action is
  # public, so nothing above it in the class may tag it.
  LUCKY_ALLOW_GUESTS = /include\s+Auth::AllowGuests\b/

  # Grip/Marten auth patterns
  GENERIC_FILTER_PATTERNS = [
    {/before_action.*auth/i, "Crystal before_action auth"},
  ]
  GENERIC_HANDLER_PATTERNS = [
    {/context\.session/, "Crystal session check"},
  ]

  # Read walking back from the route to its class/module: statements that
  # cover every route declared after them in that scope. A session read is
  # not one — it guards only the handler it sits in, and walking back to it
  # spread one route's check to every later route of the file.
  ENCLOSING_AUTH_PATTERNS = AMBER_AUTH_PATTERNS + KEMAL_FILTER_PATTERNS + LUCKY_AUTH_PATTERNS + GENERIC_FILTER_PATTERNS

  # Read inside the route's own block.
  HANDLER_AUTH_PATTERNS = KEMAL_FILTER_PATTERNS + KEMAL_HANDLER_PATTERNS + LUCKY_AUTH_PATTERNS +
                          GENERIC_FILTER_PATTERNS + GENERIC_HANDLER_PATTERNS

  # A `Kemal::Handler` subclass installed with `add_handler`, scoped by its
  # `only` / `exclude` path lists (each a {path regex, HTTP method}).
  record KemalHandler, name : String, root : String?, only : Array({Regex, String}), exclude : Array({Regex, String})

  SHARD_MANIFEST = /\Ashard\.yml\z/

  # A handler that reads who the caller is from the request and, after that
  # read, answers 401/403 or sends them to log in. A 403 issued before any
  # such read (an Origin check, a rate limit) is not an auth refusal.
  KEMAL_HANDLER_IDENTITY = /request\.headers\[\s*"authorization"|request\.cookies\b|\.session\.|current_user|basic_auth/i
  KEMAL_HANDLER_REFUSAL  = /status_code\s*(?:=|:)\s*40[13]\b|\bhalt\b[^\n]*\b40[13]\b|redirect[^\n]*(?:log_?in|sign_?in)/i

  def initialize(options : Hash(String, YAML::Any))
    super
    @kemal_handlers = [] of KemalHandler
  end

  def self.target_techs : Array(String)
    ["crystal_kemal", "crystal_amber", "crystal_lucky", "crystal_grip", "crystal_marten"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @kemal_handlers = scan_kemal_handlers
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    check_route_source(endpoint)
    return if endpoint.tags.any? { |tag| tag.tagger == "crystal_auth" }
    return unless endpoint.details.technology == "crystal_kemal"
    if handler = kemal_handler_for(endpoint)
      endpoint.add_tag(Tag.new("auth", "Protected by Kemal #{handler.name} handler", "crystal_auth"))
    end
  end

  private def kemal_handler_for(endpoint : Endpoint) : KemalHandler?
    return if @kemal_handlers.empty?
    roots = endpoint.details.code_paths.map { |path_info| nearest_project_root(path_info.path, SHARD_MANIFEST) }
    method = endpoint.method.upcase
    @kemal_handlers.find do |handler|
      next false unless roots.includes?(handler.root)
      matches = ->(rules : Array({Regex, String})) { rules.any? { |regex, verb| verb == method && regex.matches?(endpoint.url) } }
      (handler.only.empty? || matches.call(handler.only)) && !matches.call(handler.exclude)
    end
  end

  private def scan_kemal_handlers : Array(KemalHandler)
    files = collect_files_by_extension(".cr")
    installed = Hash(String, Array(String?)).new
    files.each do |file|
      next unless (content = read_file(file)) && content.includes?("add_handler")
      content.scan(/\badd_handler\s*\(?\s*(\w+)\.new\b/) do |m|
        (installed[m[1]] ||= [] of String?) << nearest_project_root(file, SHARD_MANIFEST)
      end
    end
    return [] of KemalHandler if installed.empty?

    handlers = [] of KemalHandler
    files.each do |file|
      next unless (content = read_file(file)) && content.includes?("Kemal::Handler")
      lines = content.split("\n")
      lines.each_with_index do |line, index|
        next unless (m = line.match(/^(\s*)class\s+(\w+)\s*<\s*Kemal::Handler\b/)) && (roots = installed[m[2]]?)
        body = lines[index + 1..].take_while { |l| !l.matches?(/^#{m[1]}end\b/) }.reject(&.lstrip.starts_with?('#'))
        text = body.join("\n")
        next unless read_at = body.index(&.matches?(KEMAL_HANDLER_IDENTITY))
        next unless body[read_at..].any?(&.matches?(KEMAL_HANDLER_REFUSAL))
        only, exclude = kemal_path_rules(body)
        # `only` / `exclude` declare the lists; `call` must consult them.
        only.clear unless text.includes?("only_match?")
        exclude.clear unless text.includes?("exclude_match?")
        next if only.empty? && exclude.empty?
        roots.uniq.each { |root| handlers << KemalHandler.new(m[2], root, only, exclude) }
      end
    end
    handlers
  end

  # `only ["/a", "/b/*"], "POST"` lines (method defaults to GET), with a
  # `{% for method in %w[GET POST] %}` loop around `{{ method }}` expanded.
  private def kemal_path_rules(body : Array(String)) : {Array({Regex, String}), Array({Regex, String})}
    only = [] of {Regex, String}
    exclude = [] of {Regex, String}
    loops = [] of {String, Array(String)}
    body.each do |line|
      if m = line.match(/\{%\s*for\s+(\w+)\s+in\s+%w[\[(]([^\])]*)[\])]\s*%\}/)
        loops << {m[1], m[2].split}
      elsif line.matches?(/\{%\s*end\s*%\}/)
        loops.pop?
      elsif m = line.match(/^\s*(only|exclude)\s*\(?\s*\[([^\]]*)\](?:\s*,\s*(.+?))?\s*\)?\s*$/)
        methods = if (arg = m[3]?).nil?
                    ["GET"]
                  elsif lit = arg.match(/\A"(\w+)"\z/)
                    [lit[1].upcase]
                  elsif (var = arg.match(/\A\{\{\s*(\w+)\s*\}\}\z/)) && (values = loops.reverse.find { |name, _| name == var[1] })
                    values[1].map(&.upcase)
                  else
                    next
                  end
        m[2].scan(/"([^"{}]*)"/) do |path|
          # Kemal matches through its radix tree: `*rest` globs the remainder,
          # `:id` one segment.
          pattern = path[1].split('/').join('/') do |segment|
            if segment.starts_with?('*')
              ".*"
            elsif segment.starts_with?(':')
              "[^/]+"
            else
              Regex.escape(segment)
            end
          end
          regex = Regex.new("\\A#{pattern}/?\\z")
          methods.each { |verb| (m[1] == "only" ? only : exclude) << {regex, verb} }
        end
      end
    end
    {only, exclude}
  end

  private def check_route_source(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      # Check for auth patterns in enclosing scope
      description = check_enclosing_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "crystal_auth"))
        return
      end

      # Check route handler body
      description = check_handler_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "crystal_auth"))
        return
      end
    end
  end

  private def check_enclosing_auth(lines : Array(String), route_line : Int32) : String?
    idx = route_line
    while idx >= 0
      current = lines[idx].strip
      return if current.matches?(LUCKY_ALLOW_GUESTS)

      ENCLOSING_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      # Stop at module/class definition
      break if current.starts_with?("module ") || current.starts_with?("class ")
      idx -= 1
    end

    nil
  end

  # The route's own `do ... end`: the route line and the lines indented
  # under it.
  private def check_handler_auth(lines : Array(String), route_line : Int32) : String?
    indent = lines[route_line].size - lines[route_line].lstrip.size
    (route_line...lines.size).each do |idx|
      current = lines[idx].strip
      next if current.empty?
      break if idx > route_line && lines[idx].size - lines[idx].lstrip.size <= indent

      HANDLER_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    nil
  end
end
