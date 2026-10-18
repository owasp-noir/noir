require "../common"
require "../inspect"

# `noir reach <FILE[:LINE]> [paths...] [scan flags]`
#
# Reverse lookup: which endpoints are declared in, call into, or are
# guarded/validated/sunk in this file. Each row carries the evidence
# (`via`) from that file.
module Noir::CLI::ReachCommand
  # `src/users.go:42` → {"src/users.go", 42}. A trailing `:N` is only a
  # line when N is digits, so a Windows drive or a path with a colon is
  # left alone.
  def self.parse_target(arg : String) : {String, Int32?}
    if m = arg.match(/\A(.+):(\d+)\z/)
      {m[1], m[2].to_i}
    else
      {arg, nil}
    end
  end

  def self.run(argv : Array(String))
    common = Inspect.parse_common(argv)
    if common.help
      print_help
      exit
    end
    Noir::CLI.die("noir reach: #{common.errors.join("; ")}", Inspect::EXIT_USAGE) unless common.errors.empty?

    positionals, scan_args = Inspect.split_positionals(common.rest)
    target = positionals.first?
    unless target
      Noir::CLI.die("noir reach: expected <FILE[:LINE]> first. Run `noir reach --help`.", Inspect::EXIT_USAGE)
    end
    file, line = parse_target(target)

    endpoints = Inspect.load(common, scan_args + positionals[1..])
    rows = Inspect.reach(endpoints, file, line, common.full)
    exit(Inspect.emit(rows, common))
  end

  def self.print_help(io : IO = STDOUT)
    io.puts <<-HELP
      #{Noir::CLI.section("USAGE:")}
        noir reach <FILE[:LINE]> [paths...] [flags]

      Lists the endpoints that touch FILE — declared there, calling into it, or
      guarded / validated / sunk there — with the evidence in `via`. FILE is a
      path suffix (`users.go`, `api/users.go`). With `:LINE`, evidence is
      ordered by distance to that line and `nearest_line` is set; Noir records
      declaration lines, not function spans, so the line orders rather than
      filters.

      #{Noir::CLI.section("EXAMPLES:")}
        noir reach src/handlers/users.go:57 ./app
        noir reach users.go --from report.json -f text

      #{Noir::CLI.section("OPTIONS:")}
      #{Inspect.common_help}
      HELP
  end
end
