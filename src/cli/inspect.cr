require "json"
require "levenshtein"
require "../models/endpoint"
require "../utils/url_path"
require "../utils/http_symbols"
require "./common"
require "./scan_flags"
require "./commands/scan"

# Shared machinery of the query verbs: `noir trace`, `noir reach`,
# `noir query`. Each is a view over the endpoint list a scan produces —
# the verbs filter and project, they do not analyze.
#
# The endpoints come from a live scan (every `scan` flag accepted, with
# `--ai-context all --include callee` implied) or, with `--from`, from a
# `noir scan -f json` / `-f jsonl` report, so an agent pays for one scan
# and asks many questions.
module Noir::CLI::Inspect
  FORMATS = %w[jsonl json text]

  # grep's convention, so a shell or an agent can branch without parsing.
  EXIT_MATCH    = 0
  EXIT_NO_MATCH = 1
  EXIT_USAGE    = 2

  # Flags the verbs own. Everything else in argv is scan's (flags, paths).
  record Common,
    from : String?,
    format : String,
    full : Bool,
    limit : Int32?,
    count : Bool,
    help : Bool,
    rest : Array(String),
    errors : Array(String)

  def self.parse_common(argv : Array(String)) : Common
    from = nil
    format = "jsonl"
    full = false
    limit = nil
    count = false
    help = false
    rest = [] of String
    errors = [] of String

    i = 0
    while i < argv.size
      arg = argv[i]
      case arg
      when "-h", "--help" then help = true
      when "--full"       then full = true
      when "--count"      then count = true
      when "--from", "-f", "--format", "--limit"
        value = argv[i + 1]?
        if value.nil?
          errors << "#{arg} requires a value"
        else
          i += 1
          case arg
          when "--from" then from = value
          when "--limit"
            n = value.to_i?
            n && n > 0 ? (limit = n) : (errors << "--limit must be a positive integer, got #{value}")
          else
            format = value == "plain" ? "text" : value
          end
        end
      when .starts_with?("--from=")   then from = arg[7..]
      when .starts_with?("--format=") then format = arg[9..] == "plain" ? "text" : arg[9..]
      when .starts_with?("-f=")       then format = arg[3..] == "plain" ? "text" : arg[3..]
      when .starts_with?("--limit=")
        n = arg[8..].to_i?
        n && n > 0 ? (limit = n) : (errors << "--limit must be a positive integer, got #{arg[8..]}")
      when "--"
        rest.concat(argv[i..])
        break
      else
        rest << arg
      end
      i += 1
    end

    errors << "unknown format \"#{format}\". Valid: #{FORMATS.join(", ")}" unless FORMATS.includes?(format)
    Common.new(from, format, full, limit, count, help, rest, errors)
  end

  # Splits `rest` into positionals and the scan flags (with their values).
  # Which flags consume a value is read off `ScanFlags`, the same table the
  # completions use; an unknown flag is passed through for scan's parser to
  # reject with its own message.
  def self.split_positionals(args : Array(String)) : {Array(String), Array(String)}
    positionals = [] of String
    flags = [] of String
    i = 0
    while i < args.size
      arg = args[i]
      if arg == "--"
        positionals.concat(args[i + 1..])
        break
      elsif arg.starts_with?("-") && arg.size > 1
        flags << arg
        unless arg.includes?("=")
          flag = ScanFlags::FLAGS.find(&.names.includes?(arg))
          if flag && flag.takes_value? && (value = args[i + 1]?)
            flags << value
            i += 1
          end
        end
      else
        positionals << arg
      end
      i += 1
    end
    {positionals, flags}
  end

  # The endpoint list to query: a saved report or a live scan.
  def self.load(common : Common, scan_argv : Array(String)) : Array(Endpoint)
    if from = common.from
      # Nothing is scanned, so a scan path or flag here is a mistake — and a
      # mistyped filter (`--no-gaurd`) would otherwise return the whole
      # surface as if it were the answer.
      unexpected = report_scan_args(scan_argv)
      unless unexpected.empty?
        Noir::CLI.die("--from reads a report and scans nothing; unexpected argument(s): #{unexpected.join(" ")}", EXIT_USAGE)
      end
      load_report(from)
    else
      unknown = unknown_flags(scan_argv)
      unless unknown.empty?
        Noir::CLI.die("unknown flag(s): #{unknown.join(" ")}. Run `noir scan --help` for the scan flags a verb accepts.", EXIT_USAGE)
      end
      options, args = ScanCommand.parse_options(scan_argv)
      options["ai_context"] = YAML::Any.new(true)
      options["ai_context_features"] = YAML::Any.new("")
      options["include_callee"] = YAML::Any.new(true)
      ScanCommand.prepare!(options, args)
      ScanCommand.collect(options).endpoints
    end
  end

  # Global output flags are already applied by the router, and remain valid
  # when a verb reads a report instead of scanning a path.
  def self.report_scan_args(scan_argv : Array(String)) : Array(String)
    scan_argv.reject { |arg| Noir::CLI::GLOBAL_FLAGS.includes?(arg) }
  end

  # Flags scan's parser would reject. Caught here so the verb keeps its exit
  # code 2 instead of scan's usage page and exit 1.
  def self.unknown_flags(scan_argv : Array(String)) : Array(String)
    scan_argv.select do |arg|
      next false unless arg.starts_with?('-') && arg.size > 1
      name = arg.split('=', 2)[0]
      ScanFlags::FLAGS.none?(&.names.includes?(name)) && !Legacy::LEGACY_FLAG_ALIASES.has_key?(name)
    end
  end

  # Reads the endpoints of a `-f json` document or a `-f jsonl` stream.
  # Passive findings and failure lines (jsonl) are told apart by shape.
  def self.load_report(path : String) : Array(Endpoint)
    text = File.read(path)
    # A `-f json` document parses whole; a `-f jsonl` stream does not (or is
    # a single endpoint line), so it falls back to one object per line.
    report = false
    objects = begin
      doc = JSON.parse(text)
      if doc.as_h? && (list = doc["endpoints"]?)
        report = true
        list.as_a
      else
        [doc]
      end
    rescue JSON::ParseException
      text.each_line.compact_map { |line| line.blank? ? nil : JSON.parse(line) }.to_a
    end
    endpoints = objects.compact_map do |obj|
      next unless obj.as_h? && obj["url"]? && obj["method"]?
      Endpoint.from_json(obj.to_json)
    end
    if !report && endpoints.empty?
      Noir::CLI.die("--from #{path}: not a noir report (expected `noir scan -f json` or `-f jsonl` output)", EXIT_USAGE)
    end
    endpoints
  rescue ex : IO::Error | JSON::ParseException | JSON::SerializableError
    Noir::CLI.die("--from #{path}: #{ex.message}", EXIT_USAGE)
  end

  # Guards that gate *who* may call the route. Rate limiting is a guard the
  # augmentor records, but "no auth" is what `--no-guard` asks.
  def self.auth_guards(context : AIContext?) : Array(AIContextEntry)
    return [] of AIContextEntry unless context
    context.guards.reject { |g| g.kind == "rate_limit_guard" }
  end

  # Signals worth filtering on: the route/detector/method ones restate
  # method, url and tech, and would make `--signal any` match everything.
  def self.derived_signals(context : AIContext?) : Array(AIContextEntry)
    return [] of AIContextEntry unless context
    context.signals.reject { |s| RESTATING_SIGNAL_SOURCES.includes?(s.source) }
  end

  # Evidence tying an endpoint to a file (`reach`). `path` is set only when
  # the evidence sits in a different file than the row's `path` (a shared
  # basename, a merged copy), so the agent is never sent to the wrong file.
  struct Via
    include JSON::Serializable
    property kind : String
    @[JSON::Field(ignore_serialize: name.nil?)]
    property name : String?
    @[JSON::Field(ignore_serialize: line.nil?)]
    property line : Int32?
    @[JSON::Field(ignore_serialize: path.nil?)]
    property path : String?

    def initialize(@kind, @name = nil, @line = nil, @path = nil)
    end

    def to_text : String
      String.build do |io|
        io << kind
        io << ':' << name if name
        if p = path
          io << '@' << p
          io << ':' << line if line
        elsif line
          io << '@' << line
        end
      end
    end
  end

  RESTATING_SIGNAL_SOURCES = {"route", "detector", "http_method"}

  # One output row. Compact by default: a projection of what `Endpoint`
  # already carries, empty buckets omitted. `--full` carries the unchanged
  # endpoint instead, so an agent escalates without learning a second schema.
  struct Row
    include JSON::Serializable
    property method : String
    property url : String
    @[JSON::Field(ignore_serialize: path.nil?)]
    property path : String?
    @[JSON::Field(ignore_serialize: line.nil?)]
    property line : Int32?
    # How many files declare this route (the optimizer merges copies). Set
    # only above one, so the agent knows `path` is one of several.
    @[JSON::Field(ignore_serialize: declarations.nil?)]
    property declarations : Int32?
    # The monorepo project the route belongs to (`details.project`); set only
    # when it has one.
    @[JSON::Field(ignore_serialize: project.nil?)]
    property project : String?
    @[JSON::Field(ignore_serialize: tech.nil?)]
    property tech : String?
    @[JSON::Field(ignore_serialize: handler.nil?)]
    property handler : Handler?
    @[JSON::Field(ignore_serialize: params.empty?)]
    property params = [] of String
    @[JSON::Field(ignore_serialize: tags.empty?)]
    property tags = [] of String
    @[JSON::Field(ignore_serialize: guards.empty?)]
    property guards = [] of String
    @[JSON::Field(ignore_serialize: sinks.empty?)]
    property sinks = [] of String
    @[JSON::Field(ignore_serialize: signals.empty?)]
    property signals = [] of String
    @[JSON::Field(ignore_serialize: callees.empty?)]
    property callees = [] of String
    @[JSON::Field(ignore_serialize: matched_by.nil?)]
    property matched_by : String?
    @[JSON::Field(ignore_serialize: via.empty?)]
    property via = [] of Via
    @[JSON::Field(ignore_serialize: nearest_line.nil?)]
    property nearest_line : Int32?
    @[JSON::Field(ignore_serialize: endpoint.nil?)]
    property endpoint : Endpoint?

    def initialize(@method, @url)
    end

    def self.build(endpoint : Endpoint, full : Bool) : Row
      full ? self.full(endpoint) : compact(endpoint)
    end

    def self.full(endpoint : Endpoint) : Row
      row = new(endpoint.method, endpoint.url)
      row.endpoint = endpoint
      row
    end

    def self.compact(endpoint : Endpoint) : Row
      row = new(endpoint.method, endpoint.url)
      if location = Inspect.primary_declaration(endpoint)
        row.path = location.path
        row.line = location.line
        copies = endpoint.details.code_paths.size
        row.declarations = copies if copies > 1
      end
      row.project = endpoint.details.project unless endpoint.details.project.empty?
      row.tech = endpoint.details.technology
      row.handler = endpoint.handler
      row.params = endpoint.params.map { |p| "#{p.name}:#{p.param_type}" }
      row.tags = endpoint.tags.map(&.name).uniq!
      row.callees = endpoint.callees.map(&.name).uniq!
      if context = endpoint.ai_context
        # The same guards `--guard` counts: a rate limiter is not "who may call".
        row.guards = Inspect.auth_guards(context).map(&.name).uniq!
        row.sinks = context.sinks.map(&.kind).uniq!
        row.signals = Inspect.derived_signals(context).map do |signal|
          signal.kind == "priority_review" ? "priority_review:#{signal.name}" : signal.kind
        end.uniq!
      end
      row
    end

    def to_text : String
      # `--full` carries the record and nothing else; text has one shape.
      if ep = endpoint
        row = Row.compact(ep)
        row.matched_by = matched_by
        row.via = via
        row.nearest_line = nearest_line
        return row.to_text
      end
      String.build do |io|
        io << method << ' ' << url
        if p = path
          io << "  " << p
          io << ':' << line if line
          io << "  declarations=" << declarations if declarations
        end
        io << "  " << tech if tech
        io << "  matched_by=" << matched_by if matched_by
        if h = handler
          io << "  handler=" << h.name
          if hp = h.path
            io << '@' << hp
            io << ':' << h.line if h.line
          end
        end
        {"guards", guards, "sinks", sinks, "signals", signals, "tags", tags}.each_slice(2) do |(label, values)|
          io << "  " << label << '=' << values.as(Array(String)).join(',') unless values.as(Array(String)).empty?
        end
        io << "  via=" << via.join(',', &.to_text) unless via.empty?
      end
    end
  end

  # Directories that hold copies of an app's code rather than the app:
  # juice-shop keeps a snippet of every route under `data/static/codefixes/`
  # and the optimizer merges it with the real `server.ts` declaration.
  COPY_DIRS = Set{"codefixes", "fixtures", "fixture", "snippets", "samples", "examples", "example", "vendor", "node_modules", "test", "tests", "__tests__", "spec", "testdata"}

  # The declaration the compact row names when the optimizer merged several
  # files into one endpoint: the first one that is not under a copy
  # directory, else the first. Scan order is kept otherwise, since analyzers
  # put the declaring file first and its include chain after it (Django's
  # `apps.py` before `urls.py`).
  # ponytail: a directory-name list; `declarations` says when it mattered.
  def self.primary_declaration(endpoint : Endpoint) : PathInfo?
    paths = endpoint.details.code_paths
    paths.find { |cp| cp.path.split('/').none? { |seg| COPY_DIRS.includes?(seg) } } || paths.first?
  end

  # Prints rows in `common.format` and returns the exit code. `-f text`
  # always prints the compact line; `json`/`jsonl` honour `--full`.
  def self.emit(rows : Array(Row), common : Common, io : IO = STDOUT) : Int32
    if limit = common.limit
      rows = rows.first(limit)
    end
    if common.count
      io.puts rows.size
    else
      case common.format
      when "json" then io.puts rows.to_pretty_json
      when "text" then rows.each { |row| io.puts row.to_text }
      else             rows.each { |row| io.puts row.to_json }
      end
    end
    rows.empty? ? EXIT_NO_MATCH : EXIT_MATCH
  end

  # ---- trace: concrete request path → declared route ----------------------

  # `{id}` `:id` `<int:pk>` `[id]` `$id` `${id}` match one segment; `*`
  # `**` `{path*}` `{...rest}` `[...slug]` `[[...slug]]` `*path` `:rest*` `<path:p>`
  # `{*path}` (Spring, ASP.NET, Next.js and Starlette's `{p:path}` as the
  # optimizer writes them) and `{path...}` (Ktor, Go) match the rest
  # (Express's bare `*` is a catch-all, not one segment).
  REST_PLACEHOLDER = /\A(?:<path:[^>]*>|\*\*|\{\*[^}]*\}|\{[^}]*\*\}|\{\.\.\.[^}]*\}|\{[^}]*\.\.\.\}|\[\[\.\.\.[^\]]*\]\]|\[\.\.\.[^\]]*\]|\*[A-Za-z_]\w*|:[A-Za-z_]\w*[*+]|\*)/
  # The rest placeholders that also take zero segments, so `/files/:path*`
  # serves `/files` too. Next.js `[...slug]` (written `{*slug}`) needs one,
  # but its optional `[[...slug]]` form is written as a second, bare route.
  ZERO_OR_MORE = /\A(?:\*\*|\{\*[^}]*\}|\{[^}]*(?:\*|\.\.\.)\}|:\w+\*|\[\[)/
  # path-to-regexp v8 (Express 5) optional group: `/posts{/:id}`.
  OPTIONAL_GROUP = /\A\{(\/[^{}]*)\}/
  # `:id(\d+)` (Express 4 / Koa / Fastify) and `:id{[0-9]+}` (Hono) carry a
  # regex constraint; a trailing `?` makes the segment optional.
  # Play's `$id<\w{8}>` is one placeholder with its regex.
  ONE_PLACEHOLDER  = /\A(?:\$\{[^}]*\}|\{(?:[^{}]|\{[^{}]*\})*\}|<[^>]*>|\[[^\]]*\]|:[A-Za-z_]\w*(?:\((?:[^()]|\([^()]*\))*\)|\{(?:[^{}]|\{[^{}]*\})*\})?\??|\$[A-Za-z_]\w*(?:<[^>]*>)?)/
  PLACEHOLDER_CHAR = /[{:<\[$*]/

  # The regex a declared route matches request paths against, or nil for a
  # pattern Noir cannot turn into one.
  def self.route_regex(endpoint : Endpoint) : Regex?
    # The request is compared without its trailing slash, so the route loses
    # its own first: Django's `x/<int:pk>/` must match `/x/5`.
    route = strip_trailing_slash(request_path(endpoint.url))
    if endpoint.regex_path?
      return Regex.new("\\A#{URLPath.strip_regex_anchors(route).rchop('/')}/?\\z") rescue nil
    end
    Regex.new("\\A#{route_pattern(route)}/?\\z") rescue nil
  end

  private def self.route_pattern(route : String) : String
    parts = [] of String
    scan_placeholders(route) do |kind, text|
      case kind
      when :rest
        if text.matches?(ZERO_OR_MORE) && parts.last? == "/"
          parts.pop
          parts << "(?:/.*)?"
        else
          parts << ".*"
        end
      when :optional then parts << "(?:#{route_pattern(text)})?"
      when :one
        if (text.starts_with?(':') && text.ends_with?('?')) || (text.starts_with?('{') && text.ends_with?("?}"))
          # Express 4 `:id?` and ASP.NET `{id?}` make the slash before them
          # optional too: `/posts/:id?` serves both `/posts` and `/posts/5`.
          slash = parts.last? == "/" ? parts.pop : ""
          required = text.ends_with?('?') ? text.rchop('?') : "#{text.rchop("?}")}}"
          parts << "(?:#{slash}#{typed_segment(required)})?"
        else
          parts << typed_segment(text)
        end
      else parts << Regex.escape(text)
      end
    end
    parts.join
  end

  # A typed placeholder only takes what the router would route to it:
  # Werkzeug/Django `<int:id>` / `<uuid:id>`, ASP.NET `{id:int}` /
  # `{id:guid}`, and a chi / gorilla regex constraint (`{type:issues}`,
  # `{action:star|unstar}`). `/v1/datasets/kb-legal/documents` is not
  # `/v1/datasets/<uuid:dataset_id>/documents`, and `/o/r/info/refs` is not
  # `/{owner}/{repo}/{type:issues}/{index}`.
  private def self.typed_segment(placeholder : String) : String
    case placeholder
    when /\A<int:|\A\{\w+:(?:int|long)\}\z/ then "\\d+"
    when /\A<uuid:|\A\{\w+:guid\}\z/        then "[0-9a-fA-F]{8}-?(?:[0-9a-fA-F]{4}-?){3}[0-9a-fA-F]{12}"
    when /\A\{\w+:([^\/]+)\}\z/             then constraint_segment($1)
    when /\A:\w+[({](.+)[)}]\z/             then constraint_segment($1)
    when /\A\$\w+<(.+)>\z/                  then constraint_segment($1)
    else                                         "[^/]+"
    end
  end

  # A `{name:regex}` constraint as one segment's pattern, anchored the way
  # chi anchors it (a leading `^` / trailing `$` is optional there). A regex
  # that does not compile takes any one segment.
  # ponytail: a `.` or negated class in the constraint can still match a `/`;
  # confine it to the segment if a real route ever relies on that.
  private def self.constraint_segment(constraint : String) : String
    body = constraint.lchop('^')
    body = body.rchop('$') unless body.ends_with?("\\$")
    Regex.new(body)
    "(?:#{body})"
  rescue ArgumentError
    "[^/]+"
  end

  # Walks a route, yielding `:rest` / `:one` placeholders and `:literal`
  # characters in order. A `:verb` right after a `}` is a gRPC-transcoding
  # custom method (`/v1/{name}:cancel`), literal text rather than a param.
  private def self.scan_placeholders(route : String, &)
    scanner = route
    taken = ""
    until scanner.empty?
      if taken.ends_with?('}') && scanner.starts_with?(':')
        taken = ":"
        yield :literal, taken
      elsif m = scanner.match(REST_PLACEHOLDER)
        taken = m[0]
        yield :rest, taken
      elsif m = scanner.match(OPTIONAL_GROUP)
        yield :optional, m[1]
        taken = m[0]
      elsif m = scanner.match(ONE_PLACEHOLDER)
        taken = m[0]
        yield :one, taken
      else
        taken = scanner[0].to_s
        yield :literal, taken
      end
      scanner = scanner[taken.size..]
    end
  end

  # How specific a route is: fewer catch-all segments, then fewer placeholders,
  # then more literal text. `/u/:id` outranks `/*proxyPath` for `/u/5`.
  # Among routes with a catch-all the literal text comes first:
  # `/media/:id/*any` is more specific than `/*unmatched_route`, though it
  # has one more param.
  def self.specificity(url : String) : {Int32, Int32, Int32}
    rest = 0
    one = 0
    literal = 0
    scan_placeholders(strip_trailing_slash(request_path(url))) do |kind, text|
      case kind
      when :rest           then rest += 1
      when :one, :optional then one += 1
      else                      literal += text.size
      end
    end
    rest > 0 ? {rest, -literal, one} : {rest, one, -literal}
  end

  private def self.strip_trailing_slash(path : String) : String
    while path.size > 1 && path.ends_with?('/')
      path = path.rchop('/')
    end
    path
  end

  # The path part of an endpoint URL: `-u` prefixes a scheme+host. Any
  # other scheme (`ws://`, `cli://shopctl/users`, a deep link) names the
  # surface, so it stays: `/users` is not the CLI's `users` command.
  def self.request_path(url : String) : String
    if url =~ %r{\Ahttps?://[^/]*(/.*)?\z}i
      path = $~[1]? || "/"
      return path
    end
    url
  end

  private def self.normalize(path : String) : String
    strip_trailing_slash(request_path(path).split('#', 2)[0].split('?', 2)[0])
  end

  # Whether `query --method` lists a route declared for `declared`. An
  # `ANY` row (nginx, Apache, `router.all`) serves every HTTP verb, so
  # `--method POST` lists it, as `trace` does; `--method ANY` lists only
  # the `ANY` rows.
  def self.method_listed?(methods : Array(String), declared : String) : Bool
    declared = declared.upcase
    methods.includes?(declared) || (::synthetic_any_method?(declared) && methods.any? { |m| ::ALLOWED_HTTP_METHODS.includes?(m) })
  end

  record Match, endpoint : Endpoint, matched_by : String

  # Proxy rules that serve every path under their own, by the path-type tag
  # the analyzer sets: nginx `location /api/`, haproxy `path_beg` and Istio
  # `prefix` compare strings (`/api` serves `/apis`); Ingress and Gateway
  # API `Prefix` compare whole segments.
  STRING_PREFIX_TAGS  = {"nginx-path-type" => {"prefix", "prefix-stop"}, "haproxy-path-type" => {"prefix"}, "virtualservice-path-type" => {"prefix"}}
  SEGMENT_PREFIX_TAGS = {"ingress-path-type" => {"prefix"}, "gateway-path-type" => {"pathprefix"}}

  # Whether `endpoint` serves `path` (query and fragment already dropped)
  # as a prefix: a proxy prefix rule, or a Go ServeMux pattern ending in
  # `/`, which serves its subtree (gin's or Echo's `/x/` is one route).
  private def self.prefix_serves?(endpoint : Endpoint, path : String) : Bool
    route = request_path(endpoint.url)
    string = endpoint.tags.any? { |t| STRING_PREFIX_TAGS[t.name]?.try(&.includes?(t.description)) }
    string ||= route.ends_with?('/') && (endpoint.details.technology == "go_http" || endpoint.details.technologies.includes?("go_http"))
    return path.starts_with?(route) if string
    return false unless endpoint.tags.any? { |t| SEGMENT_PREFIX_TAGS[t.name]?.try(&.includes?(t.description)) }
    route = strip_trailing_slash(route)
    route == "/" || path.starts_with?("#{route}/")
  end

  # Whether a route declared for `declared` serves a `wanted` request method.
  # Frameworks answer HEAD from the GET route, so a HEAD request traces to it.
  def self.method_serves?(declared : String, wanted : String?) : Bool
    return true unless wanted
    declared = declared.upcase
    declared == wanted || ::synthetic_any_method?(declared) || (wanted == "HEAD" && declared == "GET")
  end

  # Routes matching a concrete request, exact matches first. A PHP front
  # controller also answers its routes under another spelling: `/index.php/x`
  # is `/x` (PATH_INFO routing, Nextcloud without pretty URLs), and Nextcloud
  # serves `/ocs/v2.php/...` as `/ocs/v1.php/...` too. Those are tried
  # against the PHP routes when the request itself matches nothing.
  def self.trace(endpoints : Array(Endpoint), method : String?, path : String) : Array(Match)
    matches = trace_path(endpoints, method, path)
    return matches unless matches.empty?
    wanted = normalize(path)
    alias_path = if wanted.starts_with?("/index.php/")
                   wanted.lchop("/index.php")
                 elsif wanted.starts_with?("/ocs/v1.php/")
                   "/ocs/v2.php" + wanted.lchop("/ocs/v1.php")
                 end
    return matches unless alias_path
    php = endpoints.select { |endpoint| endpoint.details.technology.try(&.starts_with?("php_")) }
    trace_path(php, method, alias_path)
  end

  private def self.trace_path(endpoints : Array(Endpoint), method : String?, path : String) : Array(Match)
    wanted = normalize(path)
    unslashed = request_path(path).split('#', 2)[0].split('?', 2)[0]
    exact = [] of Match
    pattern = [] of {Match, {Int32, Int32, Int32}}
    endpoints.each do |endpoint|
      next unless method_serves?(endpoint.method, method)
      route = normalize(request_path(endpoint.url))
      if route == wanted
        exact << Match.new(endpoint, "exact")
      elsif (regex = route_regex(endpoint)) && regex.matches?(wanted)
        spec = specificity(endpoint.url)
        pattern << {Match.new(endpoint, spec[0] > 0 ? "wildcard" : "pattern"), spec}
      elsif prefix_serves?(endpoint, unslashed)
        # Ranked as the catch-all it is: `/api/` reads as `/api/**`.
        pattern << {Match.new(endpoint, "prefix"), specificity("#{route.rchop('/')}/**")}
      end
    end
    # Most specific first, so `--limit 1` is the route a router would pick.
    pattern.sort_by!(&.[1])
    # A route declared for the request's own method before an any-method
    # one at the same path (a proxy redirect rule beside the app's view).
    declared, any = exact.partition { |m| !method || !::synthetic_any_method?(m.endpoint.method.upcase) }
    declared + any + pattern.map(&.[0])
  end

  # Nearest declared routes for a miss: most shared leading segments
  # (case-insensitive, placeholders count), then the closest spelling of the
  # first segment that differs (`/rest/baskets/3` → `/rest/basket/:id`), then
  # the closest length. Any method: the row names it, and "that path exists,
  # but as PATCH" is the answer a miss most often needs.
  def self.candidates(endpoints : Array(Endpoint), path : String, limit = 5) : Array(Row)
    wanted = normalize(path).split('/').reject(&.empty?)
    scored = endpoints.compact_map do |endpoint|
      segments = normalize(request_path(endpoint.url)).split('/').reject(&.empty?)
      shared = 0
      literal = 0
      segments.each_with_index do |seg, i|
        break unless (w = wanted[i]?) && (seg.compare(w, case_insensitive: true) == 0 || seg.matches?(PLACEHOLDER_CHAR))
        literal += 1 unless seg.matches?(PLACEHOLDER_CHAR)
        shared += 1
      end
      typo = if (seg = segments[shared]?) && (w = wanted[shared]?)
               Levenshtein.distance(seg.downcase, w.downcase)
             else
               Int32::MAX
             end
      # A catch-all shares every segment with everything; it is only a
      # candidate when some literal text agrees or a segment is a near miss.
      next if literal == 0 && typo > 1
      {shared, typo, (segments.size - wanted.size).abs, endpoint}
    end
    scored.sort_by! { |shared, typo, delta, ep| {-shared, typo, delta, ep.url} }
    scored.first(limit).map { |_, _, _, ep| Row.compact(ep) }
  end

  # When only a catch-all answered (`/*unmatched_route`, an SPA fallback),
  # the request may be a typo of a real route: the nearest declared routes,
  # wildcard routes left out. Empty when any match is exact or a pattern.
  def self.wildcard_only_candidates(endpoints : Array(Endpoint), matches : Array(Match), path : String) : Array(Row)
    return [] of Row if matches.empty? || matches.any? { |m| m.matched_by != "wildcard" && m.matched_by != "prefix" }
    wildcard_urls = matches.map(&.endpoint.url).to_set
    candidates(endpoints, path).reject { |row| wildcard_urls.includes?(row.url) }
  end

  # ---- reach: file[:line] → endpoints that touch it -----------------------

  # Component-wise suffix match: `users.go` and `api/users.go` both name
  # `src/api/users.go`; `sers.go` does not.
  def self.path_matches?(recorded : String?, wanted : String) : Bool
    return false unless recorded
    recorded = recorded.lchop("./")
    return false unless recorded.ends_with?(wanted)
    recorded.size == wanted.size || recorded[recorded.size - wanted.size - 1] == '/'
  end

  # Every endpoint with evidence in `file`, each with its `via` list; with
  # `line`, evidence is ordered by distance and `nearest_line` is set.
  # ponytail: declaration lines only — no function spans, so `:line` orders
  # rather than filters. Tree-sitter spans would make it a filter.
  def self.reach(endpoints : Array(Endpoint), file : String, line : Int32?, full : Bool) : Array(Row)
    file = resolve_reach_path(file)
    rows = endpoints.compact_map do |endpoint|
      via = [] of Via
      declared = nil
      endpoint.details.code_paths.each do |cp|
        next unless path_matches?(cp.path, file)
        declared ||= cp
        via << Via.new("route", nil, cp.line, cp.path)
      end
      if (handler = endpoint.handler) && path_matches?(handler.path, file)
        via << Via.new("handler", handler.name, handler.line, handler.path)
      end
      endpoint.callees.each do |callee|
        via << Via.new("callee", callee.name, callee.line, callee.path) if path_matches?(callee.path, file)
      end
      # Signals are derived from the other buckets, not located in the file.
      if context = endpoint.ai_context
        {"guard" => context.guards, "source" => context.sources, "sink" => context.sinks,
         "validator" => context.validators}.each do |kind, entries|
          entries.each do |entry|
            via << Via.new(kind, entry.name, entry.line, entry.path) if path_matches?(entry.path, file)
          end
        end
      end
      next if via.empty?
      # Static assets and merged copies repeat the same evidence verbatim.
      via.uniq! { |v| {v.kind, v.name, v.line, v.path} }
      if line
        via.sort_by! { |v| (l = v.line) ? (l - line).abs : Int32::MAX }
      end
      row = Row.build(endpoint, full)
      # The row names the declaration in *this* file, not whichever merged
      # copy the optimizer listed first.
      if declared && !full
        row.path = declared.path
        row.line = declared.line
      end
      # Evidence in the row's own file needs no path; the rest keeps one.
      own = row.path || declared.try(&.path)
      via.map! { |v| v.path = nil if v.path == own; v }
      row.via = via
      row.nearest_line = via.first.line if line
      row
    end
    if line
      rows.sort_by! { |row| (l = row.nearest_line) ? (l - line).abs : Int32::MAX }
    end
    rows
  end

  private def self.resolve_reach_path(file : String) : String
    return file.lchop("./") unless file.starts_with?("./") || Path.new(file).absolute?

    absolute = File.expand_path(file)
    cwd = File.expand_path(".")
    prefix = cwd.ends_with?(File::SEPARATOR_STRING) ? cwd : "#{cwd}#{File::SEPARATOR_STRING}"
    absolute.starts_with?(prefix) ? absolute[prefix.size..] : absolute
  end

  # ---- query: AND-ed filters, comma lists OR ------------------------------

  record Filters,
    methods : Array(String) = [] of String,
    url : String? = nil,
    path : String? = nil,
    projects : Array(String) = [] of String,
    handler : String? = nil,
    techs : Array(String) = [] of String,
    tags : Array(String) = [] of String,
    params : Array(String) = [] of String,
    param_types : Array(String) = [] of String,
    protocols : Array(String) = [] of String,
    guard : Bool? = nil,
    sinks : Array(String) = [] of String,
    sources : Array(String) = [] of String,
    signals : Array(String) = [] of String,
    validators : Array(String) = [] of String do
    def matches?(endpoint : Endpoint) : Bool
      return false unless methods.empty? || Inspect.method_listed?(methods, endpoint.method)
      return false unless (u = url).nil? || Inspect.glob_or_substring?(u, endpoint.url)
      return false unless (p = path).nil? || endpoint.details.code_paths.any? { |cp| Inspect.path_glob?(p, cp.path) }
      return false unless projects.empty? || projects.any? { |wanted| Inspect.project_matches?(wanted, endpoint.details.project) }
      return false unless (h = handler).nil? || endpoint.handler.try { |eh| Inspect.glob_or_substring?(h, eh.name) || Inspect.path_glob?(h, eh.path || "") }
      unless techs.empty?
        have = endpoint.details.technologies.empty? ? [endpoint.details.technology].compact : endpoint.details.technologies
        return false unless (have & techs).present?
      end
      return false unless tags.empty? || endpoint.tags.any? { |t| tags.includes?(t.name) }
      # One parameter has to satisfy both `--param` and `--param-type`.
      unless params.empty? && param_types.empty?
        return false unless endpoint.params.any? { |p| param_matches?(p) }
      end
      return false unless protocols.empty? || protocols.includes?(endpoint.protocol)
      context = endpoint.ai_context
      unless (g = guard).nil?
        return false unless g == !Inspect.auth_guards(context).empty?
      end
      return false unless Inspect.bucket_matches?(sinks, context.try(&.sinks))
      return false unless Inspect.bucket_matches?(sources, context.try(&.sources))
      return false unless Inspect.bucket_matches?(signals, Inspect.derived_signals(context))
      return false unless Inspect.bucket_matches?(validators, context.try(&.validators))
      true
    end

    private def param_matches?(param : Param) : Bool
      return false unless params.empty? || params.any? do |name|
                            param.param_type == "header" ? name.compare(param.name, case_insensitive: true) == 0 : name == param.name
                          end
      param_types.empty? || param_types.includes?(param.param_type) || param_types.includes?(param.request_type)
    end
  end

  # `any` (or an empty bucket filter) is satisfied by a non-empty bucket.
  def self.bucket_matches?(wanted : Array(String), entries : Array(AIContextEntry)?) : Bool
    return true if wanted.empty?
    return false if entries.nil? || entries.empty?
    wanted.includes?("any") || entries.any? { |e| wanted.includes?(e.kind) }
  end

  # A glob when it looks like one, a substring otherwise. The glob is the
  # agent's, not the shell's: `*` and `**` match anything including `/`
  # (every Django URL ends in `/`, `*users*` has to find it), `?` one
  # character, `[...]` a class, and `{`, `}` are literal so a route with
  # `{id}` in it can be matched as written.
  GLOB_CHARS = /[*?\[]/

  def self.glob_or_substring?(pattern : String, value : String) : Bool
    return value.includes?(pattern) unless pattern.matches?(GLOB_CHARS)
    glob_regex(pattern).matches?(value)
  end

  # Reported paths carry the scan root (`corpus/app/routes/x.ts`), so a glob
  # written from inside the app (`routes/*`) also matches from any `/`.
  def self.path_glob?(pattern : String, value : String) : Bool
    return value.includes?(pattern) unless pattern.matches?(GLOB_CHARS)
    return glob_regex(pattern).matches?(value) if pattern.starts_with?('/') || pattern.starts_with?('*')
    glob_regex(pattern, anchored: false).matches?(value)
  end

  # A project is named by its directory under the scan base, so `services/orders`
  # is that project and not `services/orders-v2`. A glob (same rules as above)
  # matches the whole name. An endpoint with no project matches nothing.
  def self.project_matches?(wanted : String, project : String) : Bool
    return false if project.empty?
    return glob_regex(wanted).matches?(project) if wanted.matches?(GLOB_CHARS)
    wanted.chomp('/') == project
  end

  @@glob_regexes = Hash(String, Regex).new

  private def self.glob_regex(pattern : String, anchored : Bool = true) : Regex
    @@glob_regexes["#{anchored}:#{pattern}"] ||= begin
      body = String.build do |io|
        pattern.each_char do |c|
          case c
          when '*' then io << ".*"
          when '?' then io << '.'
          when '[' then io << '['
          when ']' then io << ']'
          else          io << Regex.escape(c.to_s)
          end
        end
      end
      Regex.new("#{anchored ? "\\A" : "(?:\\A|/)"}#{body}\\z")
    rescue ArgumentError
      # An unbalanced `[`: it was not a glob after all, so substring.
      Regex.new(Regex.escape(pattern))
    end
  end

  # Filter values that no endpoint can satisfy, so a typo (`--sink file`
  # for `file_io`) or a report scanned without `--ai-context` is said out
  # loud instead of returning an empty answer that looks final.
  def self.filter_warnings(endpoints : Array(Endpoint), filters : Filters) : Array(String)
    warnings = [] of String
    asks_context = !filters.guard.nil? || !(filters.sinks.empty? && filters.sources.empty? && filters.signals.empty? && filters.validators.empty?)
    if asks_context && endpoints.none?(&.ai_context)
      warnings << "no endpoint carries ai_context; scan with --ai-context (or drop --from)"
      return warnings
    end
    contexts = endpoints.compact_map(&.ai_context)
    {
      {"method", filters.methods, endpoints.map(&.method.upcase)},
      {"tech", filters.techs, endpoints.flat_map { |e| e.details.technologies.empty? ? [e.details.technology].compact : e.details.technologies }},
      {"tag", filters.tags, endpoints.flat_map(&.tags.map(&.name))},
      {"param", filters.params, endpoints.flat_map(&.params.map(&.name))},
      {"param type", filters.param_types, endpoints.flat_map { |e| e.params.flat_map { |p| [p.param_type, p.request_type] } }},
      {"project", filters.projects.reject(&.matches?(GLOB_CHARS)).map(&.chomp('/')), endpoints.map(&.details.project).reject(&.empty?)},
      {"protocol", filters.protocols, endpoints.map(&.protocol)},
      {"sink kind", filters.sinks, contexts.flat_map(&.sinks.map(&.kind))},
      {"source kind", filters.sources, contexts.flat_map(&.sources.map(&.kind))},
      {"signal kind", filters.signals, contexts.flat_map { |c| derived_signals(c).map(&.kind) }},
      {"validator kind", filters.validators, contexts.flat_map(&.validators.map(&.kind))},
    }.each do |label, wanted, seen|
      seen = seen.uniq.sort!
      unknown = wanted.reject do |k|
        k == "any" || seen.includes?(k) ||
          (label == "method" && method_listed?([k], "ANY") && seen.any? { |m| ::synthetic_any_method?(m) }) ||
          (label == "param" && endpoints.any? do |e|
            e.params.any? { |p| p.param_type == "header" && p.name.compare(k, case_insensitive: true) == 0 }
          end)
      end
      next if unknown.empty?
      # A signal the compact row hides (it restates method/url/tech) is not
      # "unknown"; say why it does not filter.
      if label == "signal kind"
        restating = contexts.flat_map { |c| c.signals.select { |s| RESTATING_SIGNAL_SOURCES.includes?(s.source) }.map(&.kind) }.uniq!
        hidden, unknown = unknown.partition { |k| restating.includes?(k) }
        warnings << "signal #{hidden.join(", ")} restates the row's method, url or tech and does not filter" unless hidden.empty?
        next if unknown.empty?
      end
      warnings << "no endpoint carries #{label} #{unknown.join(", ")}; in this report: #{seen.empty? ? "(none)" : seen.join(", ")}"
    end
    warnings
  end

  def self.query(endpoints : Array(Endpoint), filters : Filters, full : Bool) : Array(Row)
    endpoints.select { |e| filters.matches?(e) }.map { |e| Row.build(e, full) }
  end

  # The `--from / -f / --full / --limit / --count` block every verb's help
  # page shares.
  def self.common_help : String
    <<-HELP
        --from <report>        Read endpoints from a `noir scan -f json|jsonl` report instead of scanning
        -f, --format <fmt>     jsonl (default), json, or text
        --full                 Emit the full endpoint record (jsonl/json; text keeps its one line)
        --limit <n>            Print at most n rows
        --count                Print only the number of matches
        Any `noir scan` flag (-b, --exclude-path, --only-techs, -t, -u, --config-file, ...);
                             not with --from, which scans nothing

      #{Noir::CLI.section("EXIT CODES:")}
        0 matched, 1 nothing matched, 2 usage error
      HELP
  end
end
