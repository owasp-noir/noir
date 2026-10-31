require "../common"
require "../inspect"

# `noir trace "<METHOD> <URL>" [paths...] [scan flags]`
#
# Maps a concrete request (the thing an agent has in hand: a log line, a
# proxy entry) back to the declared route and prints the whole record:
# handler location, params, guards, sources, sinks, validators, signals,
# callees, tags. A miss prints the nearest routes so the next guess is
# informed, and exits 1.
module Noir::CLI::TraceCommand
  record Target, method : String?, path : String

  # `"POST /x"`, `POST /x`, or `/x` (every method). Returns the target and
  # the positionals left over, which are scan paths.
  def self.parse_target(positionals : Array(String)) : {Target?, Array(String)}
    first = positionals.first?.try(&.strip)
    return {nil, positionals} unless first
    if first.includes?(' ')
      method, path = first.split(' ', 2).map(&.strip)
      # `FOO /x` names no method; a bare `GET ` has no path.
      return {nil, positionals} if path.empty? || !::endpoint_method_token?(method)
      return {Target.new(method.upcase, path), positionals[1..]}
    end
    if ::endpoint_method_token?(first)
      path = positionals[1]?
      return {nil, positionals} unless path
      return {Target.new(first.upcase, path), positionals[2..]}
    end
    return {Target.new(nil, first), positionals[1..]} if first.starts_with?('/') || first.includes?("://")
    {nil, positionals}
  end

  def self.run(argv : Array(String))
    common = Inspect.parse_common(argv)
    if common.help
      print_help
      exit
    end
    Noir::CLI.die("noir trace: #{common.errors.join("; ")}", Inspect::EXIT_USAGE) unless common.errors.empty?

    positionals, scan_args = Inspect.split_positionals(common.rest)
    target, paths = parse_target(positionals)
    unless target
      Noir::CLI.die("noir trace: expected \"<METHOD> <URL>\" or <URL> first. Run `noir trace --help`.", Inspect::EXIT_USAGE)
    end

    endpoints = Inspect.load(common, scan_args + paths)
    matches = Inspect.trace(endpoints, target.method, target.path)
    label = "#{target.method || "ANY"} #{target.path}"

    if matches.empty?
      candidates = Inspect.candidates(endpoints, target.path)
      if limit = common.limit
        candidates = candidates.first(limit)
      end
      if common.count
        puts 0
      elsif common.format == "text"
        puts "no match: #{label}"
        candidates.each { |row| puts "candidate: #{row.to_text}" }
      else
        puts({"query" => label, "match" => false, "candidates" => candidates}.to_json)
      end
      exit(Inspect::EXIT_NO_MATCH)
    end

    # trace defaults to the full record: the point of the verb is everything
    # Noir knows about the one route. `-f text` keeps the compact line.
    full = common.full || common.format != "text"
    rows = matches.map do |match|
      row = Inspect::Row.build(match.endpoint, full)
      row.matched_by = match.matched_by
      row
    end
    status = Inspect.emit(rows, common)
    unless common.count
      candidates = Inspect.wildcard_only_candidates(endpoints, matches, target.path)
      candidates = candidates.first(limit) if limit = common.limit
      unless candidates.empty?
        if common.format == "text"
          candidates.each { |row| puts "candidate: #{row.to_text}" }
        else
          puts({"query" => label, "only_wildcard" => true, "candidates" => candidates}.to_json)
        end
      end
    end
    exit(status)
  end

  def self.print_help(io : IO = STDOUT)
    io.puts <<-HELP
      #{Noir::CLI.section("USAGE:")}
        noir trace "<METHOD> <URL>" [paths...] [flags]
        noir trace <URL> [paths...] [flags]              # every method at that path

      Maps a concrete request path to its declared route: `/api/users/42`
      matches `/api/users/{id}`, `:id`, `<int:pk>`, `[id]`, `*`. Prints the full
      endpoint record (handler, params, guards, sinks, callees, ...). On a miss,
      prints the nearest routes as candidates and exits 1. Pattern matches are
      ordered most-specific first (`matched_by`: exact, pattern, wildcard, or
      prefix for a proxy prefix location or a Go ServeMux `/x/` subtree); a
      HEAD request also traces to the GET route. Every match is printed, since
      which one a router picks is the framework's rule; the first is the best.

      #{Noir::CLI.section("EXAMPLES:")}
        noir trace "POST /api/users/42" ./app
        noir trace /login --from report.json -f text

      #{Noir::CLI.section("OPTIONS:")}
      #{Inspect.common_help}
      HELP
  end
end
