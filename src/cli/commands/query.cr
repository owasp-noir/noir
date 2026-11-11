require "../common"
require "../inspect"

# `noir query [filters] [paths...] [scan flags]`
#
# Attack-surface search. Filters AND together; a comma list inside one
# filter is OR. `--sink any` / `--signal any` / `--source any` match a
# non-empty bucket. `--exclude <filter>=<value>` drops what that filter
# would match.
module Noir::CLI::QueryCommand
  # Filter flags and the `Filters` field each one fills. Every one takes a
  # value except the guard switches.
  VALUE_FLAGS = %w[--method --url --path --project --handler --tech --tag --param --param-type --protocol --sink --source --signal --validator]

  # One pattern each: a URL or path can hold a comma (matrix params, Rails
  # formats), so the value is not split into an OR list.
  SINGLE_PATTERN_FLAGS = %w[--url --path --handler]

  # `--exclude` keys: every value filter, named without its dashes. The guard
  # switches already come as a pair, so `guard` is not one.
  EXCLUDE_KEYS = VALUE_FLAGS.map(&.lchop("--"))

  record Parsed, filters : Inspect::Filters, rest : Array(String), errors : Array(String),
    excludes : Array(Inspect::Filters) = [] of Inspect::Filters

  def self.parse_filters(args : Array(String)) : Parsed
    rest = [] of String
    errors = [] of String
    values = new_values
    excludes = [] of Inspect::Filters
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
        items = split_value(name, value)
        # `--sink ''` would otherwise be no filter at all, silently.
        if items.empty?
          errors << "#{name} requires a value"
        else
          values[name].concat(items)
        end
      when "--exclude"
        value = inline
        if value.nil?
          i += 1
          value = args[i]?
        end
        if excluded = parse_exclude(value, errors)
          excludes << excluded
        end
      when "--"
        rest.concat(args[i..])
        break
      else
        rest << arg
      end
      i += 1
    end

    Parsed.new(build_filters(values, guard), rest, errors, excludes)
  end

  private def self.new_values : Hash(String, Array(String))
    Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
  end

  # A comma list is OR, except for the one-pattern flags.
  private def self.split_value(flag : String, value : String?) : Array(String)
    return [] of String if value.nil?
    return value.blank? ? [] of String : [value] if SINGLE_PATTERN_FLAGS.includes?(flag)
    value.split(',').map(&.strip).reject(&.empty?)
  end

  # `--exclude protocol=cli` is the `--protocol cli` filter, kept apart so
  # the endpoints it matches are dropped instead of kept.
  private def self.parse_exclude(value : String?, errors : Array(String)) : Inspect::Filters?
    key, _, pattern = (value || "").partition('=')
    key = key.strip
    if key == "guard"
      errors << "--exclude guard: use --guard or --no-guard"
      return
    end
    unless EXCLUDE_KEYS.includes?(key)
      errors << "--exclude expects <filter>=<value> with a filter of #{EXCLUDE_KEYS.join(", ")}"
      return
    end
    flag = "--#{key}"
    items = split_value(flag, pattern)
    if items.empty?
      errors << "--exclude #{key}= requires a value"
      return
    end
    values = new_values
    values[flag].concat(items)
    build_filters(values, nil)
  end

  private def self.build_filters(values : Hash(String, Array(String)), guard : Bool?) : Inspect::Filters
    Inspect::Filters.new(
      methods: values["--method"].map(&.upcase),
      url: values["--url"].first?,
      path: values["--path"].first?,
      projects: values["--project"],
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
      validators: values["--validator"],
    )
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
    Inspect.query_warnings(endpoints, parsed.filters, parsed.excludes).each { |w| STDERR.puts "noir query: #{w}" }
    rows = Inspect.query(endpoints, parsed.filters, common.full, parsed.excludes)
    exit(Inspect.emit(rows, common))
  end

  def self.print_help(io : IO = STDOUT)
    io.puts <<-HELP
      #{Noir::CLI.section("USAGE:")}
        noir query [filters] [paths...] [flags]

      Filters AND together; a comma list inside one filter is OR.

      #{Noir::CLI.section("FILTERS:")}
        --method GET,POST      HTTP method (an ANY route matches every HTTP method)
        --url <glob|substr>    Route URL: a glob when it contains * ? [ (* crosses /, {id} is
                               literal), a substring otherwise
        --path <glob|substr>   Source path as reported (a relative glob also matches from any /)
        --project <dir,...>    Project (nearest build manifest) of a monorepo, relative to the scan
                               base: exact, or a glob when it contains * ? [
        --handler <glob|substr> Handler name, or handler file (same glob rules)
        --tech <name,...>      Technology (e.g. go_gin, python_django)
        --tag <name,...>       Tag name (auth, admin, ...)
        --param <name,...>     Parameter name
        --param-type <t,...>   Parameter type (query, json, form, header, cookie, path);
                               with --param, one parameter must satisfy both
        --protocol <p,...>     http, ws, cli, ...
        --guard / --no-guard   Has / lacks an auth guard (ai_context.guards; rate limiting and CSRF checks do not count)
        --sink <kind,...|any>  Reaches a sink of this kind (sql, command_exec, file_io, outbound_http,
                               template_render, redirect, mass_assignment, ...)
        --source <kind,...|any> Reads a source of this kind
        --signal <kind,...|any> Carries a derived signal (idor_review, ssrf, open_redirect, ...)
        --validator <kind,...|any> Carries a validator of this kind
                               A value no endpoint carries is reported on stderr with the values seen.
        --exclude <filter>=<value>
                               Drop the endpoints that filter matches (repeatable): any filter above
                               without its dashes, same values (e.g. protocol=cli, url='/health*')

      #{Noir::CLI.section("EXAMPLES:")}
        noir query --no-guard --sink any ./app
        noir query --signal idor_review --method PUT,DELETE --from report.json
        noir query --path 'billing/**' --count ./app
        noir query --project services/orders --url /items ./mono
        noir query --exclude protocol=cli --exclude path='tests/**' --from report.json

      #{Noir::CLI.section("OPTIONS:")}
      #{Inspect.common_help}
      HELP
  end
end
