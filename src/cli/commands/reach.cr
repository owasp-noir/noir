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
    if rows.empty?
      STDERR.puts "noir reach: #{empty_hint(endpoints, file)}"
    elsif line && rows.none? { |row| row.via.any?(&.line) }
      STDERR.puts "noir reach: no line is recorded for the evidence in #{file}; :#{line} did not order anything"
    end
    exit(Inspect.emit(rows, common))
  end

  # Why nothing came back: a file Noir recorded nothing in is not the same
  # as a name it never saw, and neither means the file is unrelated.
  def self.empty_hint(endpoints : Array(Endpoint), file : String) : String
    base = File.basename(file)
    seen = endpoints.any? do |e|
      e.details.code_paths.any? { |cp| Inspect.path_matches?(cp.path, base) } ||
        e.callees.any? { |c| Inspect.path_matches?(c.path, base) } ||
        Inspect.path_matches?(e.handler.try(&.path), base)
    end
    if seen
      "Noir recorded no route, handler, callee, guard, source, sink or validator in #{file}. " \
      "Inheritance, mixins and dynamic loading are not followed; reach the subclasses or callers instead"
    else
      "no recorded location ends with #{base}; check the path, or try a shorter suffix"
    end
  end

  def self.print_help(io : IO = STDOUT)
    io.puts <<-HELP
      #{Noir::CLI.section("USAGE:")}
        noir reach <FILE[:LINE]> [paths...] [flags]

      Lists the endpoints that touch FILE — declared there, calling into it, or
      guarded / validated / sunk there — with the evidence in `via`. FILE is a
      path suffix (`users.go`, `api/users.go`); when the suffix names several
      files, each `via` entry outside the row's own file carries its path.
      With `:LINE`, evidence is ordered by distance to that line and
      `nearest_line` is set; Noir records declaration lines, not function
      spans, so the line orders rather than filters. Inheritance and dynamic
      loading are not followed.

      #{Noir::CLI.section("EXAMPLES:")}
        noir reach src/handlers/users.go:57 ./app
        noir reach users.go --from report.json -f text

      #{Noir::CLI.section("OPTIONS:")}
      #{Inspect.common_help}
      HELP
  end
end
