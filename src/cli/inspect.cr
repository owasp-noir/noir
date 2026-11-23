require "../utils/route_matcher"
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

  # `--change` categories, in the order rows are printed. The default is the
  # new side: what a reviewer of the change has to look at.
  DIFF_CHANGES    = %w[added changed removed]
  DEFAULT_CHANGES = %w[added changed]

  # The endpoint list to query: a saved report or a live scan. `changes` is
  # query's `--change` list (empty when not given). trace and reach pass nil:
  # a diff is a set of endpoints to filter, and scanning only its new side
  # behind their back would answer a question nobody asked.
  #
  # `scope`, when given, receives every endpoint the scan saw: a diff returns
  # only what changed, and `--behind-gateway` needs the rules that did not.
  # Added and changed rows are read against the new side's rules, removed
  # ones against the old side's.
  # ponytail: asked together, the two sides pool their rules, so a route
  # added under a rule the same change removed still reads as covered; a
  # diff report read with `--from` carries only its changed rows.
  def self.load(common : Common, scan_argv : Array(String), changes : Array(String)? = nil,
                scope : Array(Endpoint)? = nil) : Array(Endpoint)
    endpoints = load_endpoints(common, scan_argv, changes, scope)
    scope.concat(endpoints) if scope && scope.empty?
    endpoints
  end

  private def self.load_endpoints(common : Common, scan_argv : Array(String), changes : Array(String)?,
                                  scope : Array(Endpoint)?) : Array(Endpoint)
    if from = common.from
      # Nothing is scanned, so a scan path or flag here is a mistake — and a
      # mistyped filter (`--no-gaurd`) would otherwise return the whole
      # surface as if it were the answer.
      unexpected = report_scan_args(scan_argv)
      unless unexpected.empty?
        message = "--from reads a report and scans nothing; unexpected argument(s): #{unexpected.join(" ")}"
        if hint = report_exclude_hint(unexpected)
          message += ". #{hint}"
        end
        Noir::CLI.die(message, EXIT_USAGE)
      end
      load_report(from, changes)
    else
      unknown = unknown_flags(scan_argv)
      unless unknown.empty?
        Noir::CLI.die("unknown flag(s): #{unknown.join(" ")}. Run `noir scan --help` for the scan flags a verb accepts.", EXIT_USAGE)
      end
      options, args = ScanCommand.parse_options(scan_argv)
      # Accepted and ignored, it would look like a gate and pass every match.
      # Read off argv, not the options: a config file's `fail_on` is scan's.
      if ScanCommand.cli_flag_names(args).includes?("--fail-on")
        Noir::CLI.die("--fail-on is `noir scan`'s gate; `noir query` gates with --fail-on-match", EXIT_USAGE)
      end
      diff_flag = {"diff" => "--diff-path", "diff_ref" => "--diff-ref"}.find { |key, _| !options[key]?.to_s.empty? }.try(&.[1])
      if diff_flag && changes.nil?
        Noir::CLI.die("#{diff_flag} is supported by `noir query`", EXIT_USAGE)
      end
      if !diff_flag && changes.try(&.present?)
        Noir::CLI.die("--change needs a diff: pass --diff-ref <rev> or --diff-path <dir>, or --from a diff report", EXIT_USAGE)
      end
      # The old side keeps the context too: `--change removed` rows are
      # filtered by the same --guard / --sink as the new ones.
      options["ai_context"] = YAML::Any.new(true)
      options["ai_context_features"] = YAML::Any.new("")
      options["include_callee"] = YAML::Any.new(true)
      ScanCommand.prepare!(options, args)
      app, old = ScanCommand.collect(options)
      return app.endpoints unless old && changes
      result = app.diff(old)
      categories = change_categories(changes)
      if scope
        scope.concat(app.endpoints) unless categories == ["removed"]
        scope.concat(old.endpoints) if categories.includes?("removed")
      end
      categories.flat_map do |category|
        case category
        when "added"   then result[:added]
        when "removed" then result[:removed]
        else                result[:changed]
        end
      end
    end
  end

  def self.change_categories(changes : Array(String)) : Array(String)
    changes.empty? ? DEFAULT_CHANGES : DIFF_CHANGES & changes
  end

  # Global output flags are already applied by the router, and remain valid
  # when a verb reads a report instead of scanning a path.
  def self.report_scan_args(scan_argv : Array(String)) : Array(String)
    scan_argv.reject { |arg| Noir::CLI::GLOBAL_FLAGS.includes?(arg) }
  end

  # `--exclude-path` / `--exclude-techs` are scan flags: they keep files or
  # techs out of the analysis, so a report gives them nothing to do.
  # `query --exclude` is the one that hides rows.
  REPORT_EXCLUDE_HINTS = {
    "--exclude-path"  => "path=<glob>",
    "--exclude-techs" => "tech=<name>",
  }

  def self.report_exclude_hint(args : Array(String)) : String?
    keys = args.compact_map { |arg| REPORT_EXCLUDE_HINTS[arg.split('=', 2)[0]]? }.uniq!
    return if keys.empty?
    "To hide endpoints of a report, use `noir query --exclude #{keys.join("` or `--exclude ")}`"
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

  # Reads the endpoints of a `-f json` document or a `-f jsonl` stream, or
  # the `changes` categories of a `noir scan --diff-* -f json` report.
  # Passive findings and failure lines (jsonl) are told apart by shape.
  def self.load_report(path : String, changes : Array(String)? = nil) : Array(Endpoint)
    text = File.read(path)
    # A `-f json` document parses whole; a `-f jsonl` stream does not (or is
    # a single endpoint line), so it falls back to one object per line.
    report = false
    diff = false
    objects = begin
      doc = JSON.parse(text)
      if doc.as_h? && (list = doc["endpoints"]?)
        report = true
        list.as_a? || Noir::CLI.die("--from #{path}: expected `endpoints` to be an array", EXIT_USAGE)
      elsif doc.as_h? && DIFF_CHANGES.all? { |category| doc[category]?.try(&.as_a?) }
        Noir::CLI.die("--from #{path} is a diff report, which `noir query` reads", EXIT_USAGE) unless changes
        report = diff = true
        change_categories(changes).flat_map { |category| doc[category].as_a }
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
    if !diff && changes.try(&.present?)
      Noir::CLI.die("--change needs a diff, and --from #{path} is not a diff report (`noir scan --diff-ref <rev> -f json`)", EXIT_USAGE)
    end
    endpoints
  rescue ex : IO::Error | JSON::ParseException | JSON::SerializableError
    Noir::CLI.die("--from #{path}: #{ex.message}", EXIT_USAGE)
  end

  # Guards that gate *who* may call the route. Rate limiting and CSRF checks
  # are guards the augmentor records, but neither stops an anonymous caller,
  # and "no auth" is what `--no-guard` asks.
  NON_AUTH_GUARD_KINDS = {"rate_limit_guard", "csrf_guard"}

  def self.auth_guards(context : AIContext?) : Array(AIContextEntry)
    return [] of AIContextEntry unless context
    context.guards.reject { |g| NON_AUTH_GUARD_KINDS.includes?(g.kind) }
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
    @[JSON::Field(ignore_serialize: !resolution.try(&.present?))]
    property resolution : Hash(String, String)?
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
    @[JSON::Field(ignore_serialize: calls.empty?)]
    property calls = [] of ServiceCall
    @[JSON::Field(ignore_serialize: called_by.empty?)]
    property called_by = [] of ServiceEdge
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
      row.calls = endpoint.calls
      row.called_by = endpoint.called_by
      row.handler = endpoint.handler
      row.resolution = endpoint.resolution
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
        io << "  project=" << project if project
        io << "  " << tech if tech
        io << "  matched_by=" << matched_by if matched_by
        if h = handler
          io << "  handler=" << h.name
          if hp = h.path
            io << '@' << hp
            io << ':' << h.line if h.line
          end
        end
        if (marks = resolution) && marks.present?
          io << "  resolution=" << marks.join(',') { |claim, how| "#{claim}:#{how}" }
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

  extend Noir::RouteMatcher
  alias Match = Noir::RouteMatcher::Match
  PLACEHOLDER_CHAR = Noir::RouteMatcher::PLACEHOLDER_CHAR

  # Follow serialized service edges breadth-first. Each project/method/URL
  # is visited once, so a cycle cannot expand the trace indefinitely.
  def self.service_trace_rows(matches : Array(Match), endpoints : Array(Endpoint), full : Bool) : Array(Row)
    index = endpoints.to_h { |endpoint| {NoirAIContext::ServiceGraph.reference(endpoint), endpoint} }
    rows = matches.map do |match|
      row = Row.build(match.endpoint, full)
      row.matched_by = match.matched_by
      row
    end
    queue = matches.map { |match| {match.endpoint, match.matched_by, nil.as(Via?)} }
    seen = matches.map { |match| NoirAIContext::ServiceGraph.reference(match.endpoint) }.to_set
    cursor = 0
    while cursor < queue.size
      endpoint, matched_by, via = queue[cursor]
      cursor += 1
      if via
        row = Row.build(endpoint, full)
        row.matched_by = matched_by
        row.via << via
        rows << row
      end
      endpoint.calls.each do |call|
        call.matches.each do |edge|
          next unless callee = index[edge.endpoint]?
          next unless seen.add?(edge.endpoint)
          evidence = Via.new("service_call", "#{endpoint.details.project}: #{endpoint.method} #{endpoint.url}", edge.line, edge.path)
          queue << {callee, edge.matched_by, evidence}
        end
      end
    end
    rows
  end

  # Nearest declared routes for a miss: most shared leading segments
  # (case-insensitive, placeholders count), then the closest spelling of the
  # first segment that differs (`/rest/baskets/3` → `/rest/basket/:id`), then
  # the closest length. Any method: the row names it, and "that path exists,
  # but as PATCH" is the answer a miss most often needs.
  def self.candidates(endpoints : Array(Endpoint), path : String, limit = 5) : Array(Row)
    wanted = strip_trailing_slash(request_target(path)).split('/').reject(&.empty?)
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
    return [] of Row if matches.empty? || matches.any? { |m| !{"wildcard", "prefix", "wildcard_ci"}.includes?(m.matched_by) }
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
    validators : Array(String) = [] of String,
    # At least one claim marked with one of these (`Endpoint#resolution`).
    resolutions : Array(String) = [] of String,
    # Access atoms as `Access::Atom#to_s` spells them; an `unresolved` atom
    # spells no fragment, so a bare `unresolved` matches any.
    requires : Array(String) = [] of String,
    reachable_by : Access::Atom? = nil,
    # One OR list per `--seen-in`; the lists AND (see QueryCommand).
    seen_in : Array(Array(String)) = [] of Array(String),
    not_seen_in : Array(String) = [] of String,
    behind_gateway : Bool? = nil,
    # Read once per query by `with_gateway_rules`: a rule covers routes other
    # than its own row, so one endpoint alone cannot say.
    gateway_rules : Array(GatewayRule)? = nil do
    def matches?(endpoint : Endpoint) : Bool
      return false unless methods.empty? || Inspect.method_listed?(methods, endpoint.method)
      return false unless (u = url).nil? || Inspect.glob_or_substring?(u, endpoint.url)
      return false unless (p = path).nil? || endpoint.details.code_paths.any? { |cp| Inspect.path_glob?(p, cp.path) }
      return false unless projects.empty? || projects.any? { |wanted| Inspect.project_matches?(wanted, endpoint.details.project) }
      return false unless (h = handler).nil? || endpoint.handler.try { |eh| Inspect.glob_or_substring?(h, eh.name) || Inspect.path_glob?(h, eh.path || "") }
      return false unless techs.empty? || (Inspect.technologies(endpoint) & techs).present?
      unless seen_in.empty? && not_seen_in.empty?
        views = Inspect.views(endpoint)
        # No technology at all (a hand-made or foreign report) says nothing
        # about where the route was seen, so it is neither "in the spec" nor
        # "missing from the spec".
        return false if views.empty?
        return false unless seen_in.all? { |listed| (views & listed).present? }
        return false if (views & not_seen_in).present?
      end
      unless (b = behind_gateway).nil?
        return false unless b == Inspect.behind_gateway?(endpoint, gateway_rules || [] of GatewayRule)
      end
      return false unless tags.empty? || endpoint.tags.any? { |t| tags.includes?(t.name) }
      # One parameter has to satisfy both `--param` and `--param-type`.
      unless params.empty? && param_types.empty?
        return false unless endpoint.params.any? { |p| param_matches?(p) }
      end
      return false unless protocols.empty? || protocols.includes?(endpoint.protocol)
      return false unless resolutions.empty? || endpoint.resolution.try(&.values.any? { |how| resolutions.includes?(how) })
      context = endpoint.ai_context
      unless (g = guard).nil?
        # An outbound client declaration (Feign, `@HttpExchange`) is not served
        # here, so it is neither guarded nor open.
        return false if endpoint.internal
        return false unless g == !Inspect.auth_guards(context).empty?
      end
      return false unless Inspect.bucket_matches?(sinks, context.try(&.sinks))
      return false unless Inspect.bucket_matches?(sources, context.try(&.sources))
      return false unless Inspect.bucket_matches?(signals, Inspect.derived_signals(context))
      return false unless Inspect.bucket_matches?(validators, context.try(&.validators))
      unless requires.empty? && reachable_by.nil?
        return false if endpoint.internal
        clauses = Access.of(endpoint)
        return false unless requires.empty? || clauses.any?(&.any_of.any? { |atom| requires.includes?(atom.to_s) })
        return false if (principal = reachable_by) && Access.cell(clauses, principal) == false
      end
      true
    end

    private def param_matches?(param : Param) : Bool
      return false unless params.empty? || params.any? do |name|
                            param.param_type == "header" ? name.compare(param.name, case_insensitive: true) == 0 : name == param.name
                          end
      param_types.empty? || param_types.includes?(param.param_type) || param_types.includes?(param.request_type)
    end
  end

  # Every technology that reported the endpoint; `technologies` is only
  # serialized once two contributed.
  def self.technologies(endpoint : Endpoint) : Array(String)
    endpoint.details.technologies.empty? ? [endpoint.details.technology].compact : endpoint.details.technologies
  end

  def self.views(endpoint : Endpoint) : Array(String)
    technologies(endpoint).map { |technology| NoirTechs.view(technology) }.uniq!
  end

  # ---- --behind-gateway: which routes a gateway rule covers ---------------

  # A gateway row read as a rule. `path` is the comparable form (see
  # `gateway_key`), `url` the row as reported, for the evidence.
  record GatewayRule, type : String, path : String, url : String, method : String, location : PathInfo? do
    # A prefix rule on `/` covers everything, and is as often a static file
    # server in front of nothing (#3565), so it is not coverage.
    def catch_all? : Bool
      type == "prefix" && path == "/"
    end

    def covers?(route : String, route_method : String) : Bool
      return false unless ::synthetic_any_method?(method) || method == route_method.upcase
      return route == path if type == "exact"
      catch_all? ? route.starts_with?('/') : (route == path || route.starts_with?("#{path}/"))
    end

    def via : Via
      Via.new("gateway_#{type}", url, location.try(&.line), location.try(&.path))
    end
  end

  # Match types by the path-type tag each analyzer records. Apache's
  # `<Location>` and `ProxyPass` front the route; its Alias, Redirect and
  # RewriteRule rows answer at the server. HAProxy `path_dir` matches a
  # segment anywhere, so it is no prefix.
  GATEWAY_PATH_TYPES = {
    "nginx-path-type"          => {"prefix" => "prefix", "prefix-stop" => "prefix", "exact" => "exact"},
    "ingress-path-type"        => {"prefix" => "prefix", "exact" => "exact"},
    "gateway-path-type"        => {"pathprefix" => "prefix", "exact" => "exact"},
    "virtualservice-path-type" => {"prefix" => "prefix", "exact" => "exact"},
    "kong-path-type"           => {"prefix" => "prefix"},
    "haproxy-path-type"        => {"prefix" => "prefix", "exact" => "exact"},
    "apache-path-type"         => {"prefix" => "prefix", "proxy" => "prefix"},
  }
  # The tag that marks a row as the rewritten upstream path, not a rule a
  # client request meets.
  GATEWAY_REWRITE_SOURCES = {"ingress-path-type" => "ingress-source", "gateway-path-type" => "gateway-source",
                             "virtualservice-path-type" => "virtualservice-source"}
  # A subtree spelled in the URL: `/api/*`, `/api/**`, `{proxy+}`, `{**rest}`,
  # `:path*`, wrangler's `/api*`.
  GATEWAY_SUBTREE = %r{(?:/\*\*|/\{\*{1,2}[^{}/]*\}|/\{[^{}/]+\+\}|/:\w+\*|\*)\z}
  # Gateways that record no path-type tag, so the URL's shape says. Spring
  # PathPattern and Apigee's `MatchesPath` read a lone `*` as one segment.
  GATEWAY_URL_TECHS = Set{"apigee", "apisix", "aws_cdk", "aws_cloudformation", "caddy", "cloudflare_wrangler", "kamal", "krakend",
                          "ocelot", "serverless_framework", "spring_cloud_gateway", "terraform", "traefik", "tyk", "vercel", "yarp"}
  GATEWAY_STAR_SEGMENT_TECHS = Set{"apigee", "spring_cloud_gateway"}

  # `exact`, `prefix`, or nil when the row is no rule this version reads.
  # ponytail: regex and implementation-specific rules are not used (they
  # count only through an exact merge); envoy and netlify tag neither the
  # match type nor their rewrite/redirect rows, traefik not Path from
  # PathPrefix (read as exact). Upgrade path: a path-type tag on each.
  def self.gateway_rule_type(endpoint : Endpoint) : String?
    return if endpoint.regex_path?
    types = endpoint.tags.compact_map do |tag|
      next unless type = GATEWAY_PATH_TYPES[tag.name]?.try(&.[tag.description]?)
      if source = GATEWAY_REWRITE_SOURCES[tag.name]?
        origins = endpoint.tags.select(&.name.==(source))
        next if origins.present? && origins.all?(&.description.==("rewrite"))
      end
      type
    end
    technologies(endpoint).each do |technology|
      next unless GATEWAY_URL_TECHS.includes?(technology)
      if type = gateway_url_type(endpoint, technology)
        types << type
      end
    end
    types.includes?("prefix") ? "prefix" : types.first?
  end

  private def self.gateway_url_type(endpoint : Endpoint, technology : String) : String?
    only = ->(name : String, values : Array(String)) do
      found = endpoint.tags.select(&.name.==(name))
      found.present? && found.all? { |tag| values.includes?(tag.description) }
    end
    case technology
    when "kamal" then return only.call("kamal-source", ["proxy"]) ? "prefix" : "exact"
    when "tyk" then return endpoint.tags.any?(&.name.==("tyk-policy")) ? "exact" : "prefix" # listen_path
    when "apigee"
      return "prefix" unless endpoint.tags.any?(&.name.==("apigee-flow")) # BasePath
    when "caddy"
      return if only.call("caddy-source", ["redir", "respond"])
    when "vercel"
      return if only.call("vercel-rule", ["redirect", "header"])
    end
    url = endpoint.url
    return "exact" unless url.matches?(GATEWAY_SUBTREE)
    return if GATEWAY_STAR_SEGMENT_TECHS.includes?(technology) && url.ends_with?("/*")
    "prefix"
  end

  # The path as rules compare it: no query, no trailing slash, every
  # whole-segment placeholder spelled `{}` (as the optimizer's dedup does).
  def self.gateway_key(url : String) : String
    Noir::URLPath.unify_path_placeholders(normalize(url))
  end

  # A rule's path, its subtree spelling (`/*`, `{proxy+}`) dropped.
  private def self.gateway_rule_path(url : String) : String
    gateway_key(url.sub(GATEWAY_SUBTREE, "")).presence || "/"
  end

  def self.gateway_rules(endpoints : Array(Endpoint)) : Array(GatewayRule)
    endpoints.compact_map do |endpoint|
      next unless views(endpoint).includes?("gateway") && (type = gateway_rule_type(endpoint))
      # An Ingress rule routes every method; one folded into a code route
      # took that route's method (see the optimizer's `fold_proxy_routes`).
      any = ::synthetic_any_method?(endpoint.method) || endpoint.tags.any?(&.name.==("ingress-path-type"))
      paths = endpoint.details.code_paths
      # ponytail: a merged row does not say which file is the gateway's; the
      # merge appends the folded rule's declaration last.
      location = views(endpoint).size == 1 ? paths.first? : paths.last?
      GatewayRule.new(type, gateway_rule_path(endpoint.url), endpoint.url, any ? "ANY" : endpoint.method.upcase, location)
    end
  end

  # The longest rule covering the route, among the catch-all rules or the others.
  # ponytail: rules × routes with a string check; index by first segment if
  # a gateway with thousands of rules ever makes it slow.
  def self.gateway_rule(endpoint : Endpoint, rules : Array(GatewayRule), catch_all : Bool = false) : GatewayRule?
    route = gateway_key(endpoint.url)
    best = nil
    rules.each do |rule|
      next unless rule.catch_all? == catch_all && rule.covers?(route, endpoint.method)
      best = rule if best.nil? || rule.path.size > best.path.size
    end
    best
  end

  # Reported by a gateway itself (an exact merge), or under one of its rules.
  # A catch-all `/` merged into the route at `/` is still only a catch-all;
  # the rule's own row stays behind its gateway.
  def self.behind_gateway?(endpoint : Endpoint, rules : Array(GatewayRule)) : Bool
    return true if gateway_rule(endpoint, rules)
    views = views(endpoint)
    return false unless views.includes?("gateway")
    views.size == 1 || !(gateway_rule_type(endpoint) == "prefix" && gateway_rule_path(endpoint.url) == "/")
  end

  # `scope` is every endpoint the rules may come from: a diff queries only
  # the changed rows, and the rules in front of them did not change.
  def self.with_gateway_rules(filters : Filters, scope : Array(Endpoint)) : Filters
    return filters if filters.behind_gateway.nil? || filters.gateway_rules
    filters.copy_with(gateway_rules: gateway_rules(scope))
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
    warnings << GATEWAY_JOIN_NOTE if gateway_join?(filters)
    filters = with_gateway_rules(filters, endpoints)
    if warning = catch_all_warning(endpoints, filters)
      warnings << warning
    end
    asks_context = !filters.guard.nil? || !(filters.sinks.empty? && filters.sources.empty? && filters.signals.empty? && filters.validators.empty?)
    if asks_context && endpoints.none?(&.ai_context)
      warnings << "no endpoint carries ai_context; scan with --ai-context (or drop --from)"
      return warnings
    end
    access_atoms = filters.requires.dup
    if (principal = filters.reachable_by) && !(principal.kind.anonymous? || principal.kind.authenticated?)
      access_atoms << principal.to_s
    end
    # Without taggers every route reads as "no guard found", which
    # `--reachable-by anonymous` would return as the whole surface.
    if (access_atoms.present? || filters.reachable_by) && endpoints.all? { |e| Access.of(e).empty? }
      warnings << "no endpoint carries an access requirement (no guard tag found); a report needs `noir scan -T` or `--ai-context`"
      access_atoms.clear
    end
    contexts = endpoints.compact_map(&.ai_context)
    {
      {"method", filters.methods, endpoints.map(&.method.upcase)},
      {"tech", filters.techs, endpoints.flat_map { |e| technologies(e) }},
      # `--not-seen-in spec` on a scan with no spec keeps every route, which
      # reads like a finding; this says there was nothing to compare with.
      # `--behind-gateway` asks for the gateway view only when no rule was
      # read: a diff's rows need not hold the gateway rows behind its rules.
      {"view", filters.seen_in.flatten + filters.not_seen_in + (filters.gateway_rules.try(&.empty?) ? ["gateway"] : [] of String), endpoints.flat_map { |e| views(e) }},
      {"tag", filters.tags, endpoints.flat_map(&.tags.map(&.name))},
      {"param", filters.params, endpoints.flat_map(&.params.map(&.name))},
      {"param type", filters.param_types, endpoints.flat_map { |e| e.params.flat_map { |p| [p.param_type, p.request_type] } }},
      {"project", filters.projects.reject(&.matches?(GLOB_CHARS)).map(&.chomp('/')), endpoints.map(&.details.project).reject(&.empty?)},
      {"protocol", filters.protocols, endpoints.map(&.protocol)},
      {"resolution", filters.resolutions, endpoints.flat_map { |e| e.resolution.try(&.values) || [] of String }},
      {"sink kind", filters.sinks, contexts.flat_map(&.sinks.map(&.kind))},
      {"source kind", filters.sources, contexts.flat_map(&.sources.map(&.kind))},
      {"signal kind", filters.signals, contexts.flat_map { |c| derived_signals(c).map(&.kind) }},
      {"validator kind", filters.validators, contexts.flat_map(&.validators.map(&.kind))},
      {"access atom", access_atoms, endpoints.flat_map { |e| Access.of(e).flat_map(&.any_of.map(&.to_s)) }},
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

  GATEWAY_JOIN_NOTE = "--seen-in/--not-seen-in join gateway rules to a route only on an exact method and path; for the routes under a prefix rule use --behind-gateway or --not-behind-gateway"

  # Routes that only a catch-all `/` rule covers are not counted as behind a
  # gateway; this says how many, and which rules, so the count is not silent.
  private def self.catch_all_warning(endpoints : Array(Endpoint), filters : Filters) : String?
    return unless (rules = filters.gateway_rules) && rules.any?(&.catch_all?)
    asked = filters.copy_with(behind_gateway: nil)
    under = endpoints.compact_map do |endpoint|
      next if !asked.matches?(endpoint) || behind_gateway?(endpoint, rules)
      gateway_rule(endpoint, rules, catch_all: true)
    end
    return if under.empty?
    named = under.compact_map(&.location).map { |l| l.line ? "#{l.path}:#{l.line}" : l.path }.uniq!
    "#{under.size} route#{under.size == 1 ? " is" : "s are"} under only a catch-all `/` gateway rule and not counted as behind a gateway#{": " unless named.empty?}#{named.join(", ")}"
  end

  # A `location /api` or an Ingress `/` never equals a route under it, so
  # "served and routed" comes back empty and "not behind a gateway" comes
  # back full on a service that is all behind one. Joining gateway with
  # another view is when that reads as a finding; listing the rules is not.
  private def self.gateway_join?(filters : Filters) : Bool
    lists = filters.seen_in + (filters.not_seen_in.empty? ? [] of Array(String) : [filters.not_seen_in])
    lists.each_with_index.any? do |list, i|
      list.includes?("gateway") && lists.each_with_index.any? { |other, j| j != i && other.any? { |view| view != "gateway" } }
    end
  end

  # `excludes` are the `--exclude` filters: an endpoint any of them matches
  # is dropped, whatever the other filters say.
  def self.query(endpoints : Array(Endpoint), filters : Filters, full : Bool,
                 excludes : Array(Filters) = [] of Filters) : Array(Row)
    filters = with_gateway_rules(filters, endpoints)
    rules = filters.behind_gateway ? filters.gateway_rules : nil
    endpoints.select { |e| filters.matches?(e) && excludes.none?(&.matches?(e)) }.map do |e|
      row = Row.build(e, full)
      # The rule in front of the row, the evidence `--behind-gateway` rests on.
      if rules && (rule = gateway_rule(e, rules))
        row.via = [rule.via]
      end
      if principal = filters.reachable_by
        row.via.concat(unknown_access(e, principal))
      end
      row
    end
  end

  # The guards that leave `principal`'s cell unknown, one per unread check.
  # A kept row with none is a definite yes.
  def self.unknown_access(endpoint : Endpoint, principal : Access::Atom) : Array(Via)
    Access.of(endpoint).select { |clause| Access.cell([clause], principal).nil? }.flat_map do |clause|
      clause.any_of.select(&.kind.unresolved?).map do |atom|
        Via.new("access_unknown", (atom.value || clause.source).presence, clause.line, clause.path)
      end
    end.uniq!
  end

  # `filter_warnings` for the kept filters, then for each `--exclude`: an
  # excluded value no endpoint carries (`protocol=cil`) drops nothing, and
  # the unfiltered answer would pass for the filtered one.
  def self.query_warnings(endpoints : Array(Endpoint), filters : Filters,
                          excludes : Array(Filters) = [] of Filters) : Array(String)
    warnings = filter_warnings(endpoints, filters)
    excludes.each do |excluded|
      filter_warnings(endpoints, excluded).each do |warning|
        next if warnings.includes?(warning)
        prefixed = "--exclude: #{warning}"
        warnings << prefixed unless warnings.includes?(prefixed)
      end
    end
    warnings
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
