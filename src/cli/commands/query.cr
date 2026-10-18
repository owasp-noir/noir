require "../common"
require "../inspect"

# `noir query [filters] [paths...] [scan flags]`
#
# Attack-surface search. Filters AND together; a comma list inside one
# filter is OR. `--sink any` / `--signal any` / `--source any` match a
# non-empty bucket.
module Noir::CLI::QueryCommand
  # Filter flags and the `Filters` field each one fills. Every one takes a
  # value except the guard switches.
  VALUE_FLAGS = %w[--method --url --path --handler --tech --tag --param --param-type --protocol --sink --source --signal]

  record Parsed, filters : Inspect::Filters, rest : Array(String), errors : Array(String)

  def self.parse_filters(args : Array(String)) : Parsed
    rest = [] of String
    errors = [] of String
    values = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
    guard = nil

    i = 0
    while i < args.size
      arg = args[i]
      parts = arg.split('=', 2)
      name = parts[0]
      inline = parts[1]?
      case name
      when "--guard", "--no-guard"
        wanted = name == "--guard"
        errors << "--guard and --no-guard are exclusive" if !guard.nil? && guard != wanted
        guard = wanted
      when .in?(VALUE_FLAGS)
        value = inline
        if value.nil?
          i += 1
          value = args[i]?
        end
        if value.nil?
          errors << "#{name} requires a value"
        else
          values[name].concat(value.split(',').map(&.strip).reject(&.empty?))
        end
      when "--"
        rest.concat(args[i..])
        break
      else
        rest << arg
      end
      i += 1
    end

    filters = Inspect::Filters.new(
      methods: values["--method"].map(&.upcase),
      url: values["--url"].first?,
      path: values["--path"].first?,
      handler: values["--handler"].first?,
      techs: values["--tech"],
      tags: values["--tag"],
      params: values["--param"],
      param_types: values["--param-type"],
      protocols: values["--protocol"],
      guard: guard,
      sinks: values["--sink"],
      sources: values["--source"],
      signals: values["--signal"],
    )
    Parsed.new(filters, rest, errors)
  end

  def self.run(argv : Array(String))
    common = Inspect.parse_common(argv)
    if common.help
      print_help
      exit
    end
    parsed = parse_filters(common.rest)
    errors = common.errors + parsed.errors
    Noir::CLI.die("noir query: #{errors.join("; ")}", Inspect::EXIT_USAGE) unless errors.empty?

    positionals, scan_args = Inspect.split_positionals(parsed.rest)
    endpoints = Inspect.load(common, scan_args + positionals)
    Inspect.filter_warnings(endpoints, parsed.filters).each { |w| STDERR.puts "noir query: #{w}" }
    rows = Inspect.query(endpoints, parsed.filters, common.full)
    exit(Inspect.emit(rows, common))
  end

  def self.print_help(io : IO = STDOUT)
    io.puts <<-HELP
      #{Noir::CLI.section("USAGE:")}
        noir query [filters] [paths...] [flags]

      Filters AND together; a comma list inside one filter is OR.

      #{Noir::CLI.section("FILTERS:")}
        --method GET,POST      HTTP method
        --url <glob|substr>    Route URL (glob when it contains * ? [, substring otherwise)
        --path <glob|substr>   Source path as reported (a relative glob also matches as a suffix)
        --handler <substr|glob> Handler name contains, or handler file matches
        --tech <name,...>      Technology (e.g. go_gin, python_django)
        --tag <name,...>       Tag name (auth, admin, ...)
        --param <name,...>     Parameter name
        --param-type <t,...>   Parameter type (query, json, form, header, cookie, path)
        --protocol <p,...>     http, ws, cli, ...
        --guard / --no-guard   Has / lacks an auth guard (ai_context.guards; rate limiting does not count)
        --sink <kind,...|any>  Reaches a sink of this kind (sql, command, file_io, outbound_http,
                               template_render, redirect, mass_assignment, ...)
        --source <kind|any>    Reads a source of this kind
        --signal <kind|any>    Carries a derived signal (idor_review, ssrf, open_redirect, ...)
                               A kind no endpoint carries is reported on stderr with the kinds seen.

      #{Noir::CLI.section("EXAMPLES:")}
        noir query --no-guard --sink any ./app
        noir query --signal idor_review --method PUT,DELETE --from report.json
        noir query --path 'billing/**' --count ./app

      #{Noir::CLI.section("OPTIONS:")}
      #{Inspect.common_help}
      HELP
  end
end
