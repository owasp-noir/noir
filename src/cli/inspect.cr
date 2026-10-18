require "json"
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
            format = value
          end
        end
      when .starts_with?("--from=")   then from = arg[7..]
      when .starts_with?("--format=") then format = arg[9..]
      when .starts_with?("-f=")       then format = arg[3..]
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
      load_report(from)
    else
      options, args = ScanCommand.parse_options(scan_argv)
      options["ai_context"] = YAML::Any.new(true)
      options["ai_context_features"] = YAML::Any.new("")
      options["include_callee"] = YAML::Any.new(true)
      ScanCommand.prepare!(options, args)
      ScanCommand.collect(options).endpoints
    end
  end

  # Reads the endpoints of a `-f json` document or a `-f jsonl` stream.
  # Passive findings and failure lines (jsonl) are told apart by shape.
  def self.load_report(path : String) : Array(Endpoint)
    text = File.read(path)
    # A `-f json` document parses whole; a `-f jsonl` stream does not (or is
    # a single endpoint line), so it falls back to one object per line.
    objects = begin
      doc = JSON.parse(text)
      doc.as_h? && doc["endpoints"]? ? doc["endpoints"].as_a : [doc]
    rescue JSON::ParseException
      text.each_line.compact_map { |line| line.blank? ? nil : JSON.parse(line) }.to_a
    end
    objects.compact_map do |obj|
      next unless obj.as_h? && obj["url"]? && obj["method"]?
      Endpoint.from_json(obj.to_json)
    end
  rescue ex : File::Error | JSON::ParseException | JSON::SerializableError
    Noir::CLI.die("--from #{path}: #{ex.message}", EXIT_USAGE)
  end

  # Evidence tying an endpoint to a file (`reach`).
  struct Via
    include JSON::Serializable
    property kind : String
    @[JSON::Field(ignore_serialize: name.nil?)]
    property name : String?
    @[JSON::Field(ignore_serialize: line.nil?)]
    property line : Int32?

    def initialize(@kind, @name = nil, @line = nil)
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
    @[JSON::Field(ignore_serialize: tech.nil?)]
    property tech : String?
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
      if location = endpoint.details.code_paths.first?
        row.path = location.path
        row.line = location.line
      end
      row.tech = endpoint.details.technology
      row.params = endpoint.params.map { |p| "#{p.name}:#{p.param_type}" }
      row.tags = endpoint.tags.map(&.name).uniq!
      row.callees = endpoint.callees.map(&.name)
      if context = endpoint.ai_context
        row.guards = context.guards.map(&.name).uniq!
        row.sinks = context.sinks.map(&.kind).uniq!
        row.signals = context.signals.compact_map do |signal|
          # Route / detector / method signals restate method, url and tech.
          next if RESTATING_SIGNAL_SOURCES.includes?(signal.source)
          signal.kind == "priority_review" ? "priority_review:#{signal.name}" : signal.kind
        end.uniq!
      end
      row
    end

    def to_text : String
      String.build do |io|
        io << method << ' ' << url
        if p = path
          io << "  " << p
          io << ':' << line if line
        end
        io << "  " << tech if tech
        {"guards", guards, "sinks", sinks, "signals", signals, "tags", tags}.each_slice(2) do |(label, values)|
          io << "  " << label << '=' << values.as(Array(String)).join(',') unless values.as(Array(String)).empty?
        end
        unless via.empty?
          io << "  via=" << via.join(',') { |v| "#{v.kind}#{v.name ? ":#{v.name}" : ""}#{v.line ? "@#{v.line}" : ""}" }
        end
      end
    end
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

  # `{id}` `:id` `<int:pk>` `[id]` `$id` `${id}` `*` match one segment;
  # `**` `{path*}` `{...rest}` `[...slug]` `*path` `:rest*` match the rest.
  REST_PLACEHOLDER = /\A(?:\*\*|\{[^}]*\*\}|\{\.\.\.[^}]*\}|\[\.\.\.[^\]]*\]|\*[A-Za-z_]\w*|:[A-Za-z_]\w*\*)/
  ONE_PLACEHOLDER  = /\A(?:\$\{[^}]*\}|\{[^}]*\}|<[^>]*>|\[[^\]]*\]|:[A-Za-z_]\w*|\$[A-Za-z_]\w*|\*)/
  PLACEHOLDER_CHAR = /[{:<\[$*]/

  # The regex a declared route matches request paths against, or nil for a
  # pattern Noir cannot turn into one.
  def self.route_regex(endpoint : Endpoint) : Regex?
    route = request_path(endpoint.url)
    if endpoint.regex_path?
      return Regex.new("\\A#{URLPath.strip_regex_anchors(route).rchop('/')}/?\\z") rescue nil
    end
    pattern = String.build do |io|
      scanner = route
      until scanner.empty?
        if m = scanner.match(REST_PLACEHOLDER)
          io << ".*"
          scanner = scanner[m[0].size..]
        elsif m = scanner.match(ONE_PLACEHOLDER)
          io << "[^/]+"
          scanner = scanner[m[0].size..]
        else
          io << Regex.escape(scanner[0].to_s)
          scanner = scanner[1..]
        end
      end
    end
    Regex.new("\\A#{pattern}/?\\z")
  end

  # The path part of an endpoint URL: `-u` prefixes a scheme+host, a
  # realtime surface keeps its `ws://` form as-is.
  def self.request_path(url : String) : String
    return url if url.starts_with?("ws://") || url.starts_with?("wss://")
    if url =~ %r{\A[a-z][a-z0-9+.-]*://[^/]*(/.*)?\z}i
      path = $~[1]? || "/"
      return path
    end
    url
  end

  private def self.normalize(path : String) : String
    path = path.split('?', 2)[0]
    while path.size > 1 && path.ends_with?('/')
      path = path.rchop('/')
    end
    path
  end

  record Match, endpoint : Endpoint, matched_by : String

  # Routes matching a concrete request, exact matches first.
  def self.trace(endpoints : Array(Endpoint), method : String?, path : String) : Array(Match)
    wanted = normalize(path)
    exact = [] of Match
    pattern = [] of Match
    endpoints.each do |endpoint|
      next if method && endpoint.method.upcase != method && !::synthetic_any_method?(endpoint.method)
      route = normalize(request_path(endpoint.url))
      if route == wanted
        exact << Match.new(endpoint, "exact")
      elsif (regex = route_regex(endpoint)) && regex.matches?(wanted)
        pattern << Match.new(endpoint, "pattern")
      end
    end
    exact + pattern
  end

  # Nearest declared routes by shared leading segments, for a miss. Any
  # method: the row names it, and "that path exists, but as PATCH" is the
  # answer a miss most often needs.
  def self.candidates(endpoints : Array(Endpoint), path : String, limit = 5) : Array(Row)
    wanted = normalize(path).split('/').reject(&.empty?)
    scored = endpoints.compact_map do |endpoint|
      segments = normalize(request_path(endpoint.url)).split('/').reject(&.empty?)
      shared = 0
      segments.each_with_index do |seg, i|
        break unless (w = wanted[i]?) && (seg == w || seg.matches?(PLACEHOLDER_CHAR))
        shared += 1
      end
      next if shared == 0
      {shared, (segments.size - wanted.size).abs, endpoint}
    end
    scored.sort_by! { |shared, delta, ep| {-shared, delta, ep.url} }
    scored.first(limit).map { |_, _, ep| Row.compact(ep) }
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
    file = file.lchop("./")
    endpoints.compact_map do |endpoint|
      via = [] of Via
      endpoint.details.code_paths.each do |cp|
        via << Via.new("route", nil, cp.line) if path_matches?(cp.path, file)
      end
      endpoint.callees.each do |callee|
        via << Via.new("callee", callee.name, callee.line) if path_matches?(callee.path, file)
      end
      # Signals are derived from the other buckets, not located in the file.
      if context = endpoint.ai_context
        {"guard" => context.guards, "source" => context.sources, "sink" => context.sinks,
         "validator" => context.validators}.each do |kind, entries|
          entries.each do |entry|
            via << Via.new(kind, entry.name, entry.line) if path_matches?(entry.path, file)
          end
        end
      end
      next if via.empty?
      if line
        via.sort_by! { |v| (l = v.line) ? (l - line).abs : Int32::MAX }
      end
      row = Row.build(endpoint, full)
      row.via = via
      row.nearest_line = via.first.line if line
      row
    end
  end

  # ---- query: AND-ed filters, comma lists OR ------------------------------

  record Filters,
    methods : Array(String) = [] of String,
    url : String? = nil,
    path : String? = nil,
    techs : Array(String) = [] of String,
    tags : Array(String) = [] of String,
    params : Array(String) = [] of String,
    param_types : Array(String) = [] of String,
    protocols : Array(String) = [] of String,
    guard : Bool? = nil,
    sinks : Array(String) = [] of String,
    sources : Array(String) = [] of String,
    signals : Array(String) = [] of String do
    def matches?(endpoint : Endpoint) : Bool
      return false unless methods.empty? || methods.includes?(endpoint.method.upcase)
      return false unless (u = url).nil? || Inspect.glob_or_substring?(u, endpoint.url)
      return false unless (p = path).nil? || endpoint.details.code_paths.any? { |cp| Inspect.glob_or_substring?(p, cp.path) }
      unless techs.empty?
        have = endpoint.details.technologies.empty? ? [endpoint.details.technology].compact : endpoint.details.technologies
        return false unless (have & techs).present?
      end
      return false unless tags.empty? || endpoint.tags.any? { |t| tags.includes?(t.name) }
      return false unless params.empty? || endpoint.params.any? { |p| params.includes?(p.name) }
      return false unless param_types.empty? || endpoint.params.any? { |p| param_types.includes?(p.param_type) || param_types.includes?(p.request_type) }
      return false unless protocols.empty? || protocols.includes?(endpoint.protocol)
      context = endpoint.ai_context
      unless (g = guard).nil?
        return false unless g == !(context.nil? || context.guards.empty?)
      end
      return false unless Inspect.bucket_matches?(sinks, context.try(&.sinks))
      return false unless Inspect.bucket_matches?(sources, context.try(&.sources))
      return false unless Inspect.bucket_matches?(signals, context.try(&.signals))
      true
    end
  end

  # `any` (or an empty bucket filter) is satisfied by a non-empty bucket.
  def self.bucket_matches?(wanted : Array(String), entries : Array(AIContextEntry)?) : Bool
    return true if wanted.empty?
    return false if entries.nil? || entries.empty?
    wanted.includes?("any") || entries.any? { |e| wanted.includes?(e.kind) }
  end

  # A glob when it looks like one, a substring otherwise. `File.match?`
  # raises lazily on a malformed pattern; that falls back to substring too.
  def self.glob_or_substring?(pattern : String, value : String) : Bool
    if pattern.matches?(/[*?\[]/)
      begin
        return File.match?(pattern, value)
      rescue
      end
    end
    value.includes?(pattern)
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
        --full                 Emit the full endpoint record instead of the compact row
        --limit <n>            Print at most n rows
        --count                Print only the number of matches
        Any `noir scan` flag (-b, --exclude-path, --only-techs, -t, -u, --config-file, ...)

      #{Noir::CLI.section("EXIT CODES:")}
        0 matched, 1 nothing matched, 2 usage error
      HELP
  end
end
