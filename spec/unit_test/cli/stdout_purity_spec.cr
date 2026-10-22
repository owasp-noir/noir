require "../../spec_helper"
require "../../../src/cli/common"

# STDOUT belongs to the report. Nothing else may be written there.
#
# Noir's own diagnostics have gone through `NoirLogger` (STDERR) for a long
# time, but Crystal's *global* `Log` is a second, quieter route to the same
# stream: the stdlib configures it, at the bottom of its own `log.cr`, with a
# `Log::IOBackend` whose IO defaults to STDOUT. Anything written through it —
# by Noir, by the stdlib, or by a shard Noir depends on — lands in the middle
# of the `-f json` / `-f sarif` / `-f yaml` document and breaks every
# downstream parser.
#
# Two guards, because the hazard arrives from two directions:
#
#   1. code Noir owns, caught here at the source level;
#   2. code Noir does not own, caught at runtime by the process-entry
#      redirect this file also pins.
#
# The end-to-end proof lives in `binary_surface_spec.cr` (a HAR whose
# timestamps the `har` shard warns about), because these examples run in the
# same process as the spec runner and cannot observe the real streams: Crystal's
# spec DSL rebinds the global `Log` to `:none` at startup, so a leak is silent
# here no matter which IO it was aimed at.

private def source_files : Array(String)
  Dir.glob("src/**/*.cr").sort!
end

# Comment lines are dropped before matching: the fixes that removed these
# calls left comments *naming* them (`"was a `Log.debug` on Crystal's global
# `Log`"`), and a guard that fired on its own changelog would be useless.
private def stripped_sources : Hash(String, Array(Tuple(Int32, String)))
  source_files.to_h do |path|
    lines = [] of Tuple(Int32, String)
    File.read_lines(path).each_with_index do |line, index|
      next if line.lstrip.starts_with?('#')
      lines << {index + 1, line}
    end
    {path, lines}
  end
end

# `Log.info { ... }` and friends on the *global* logger. `logger.info`,
# `ClientLog.info` and `AuditLog.write` are all excluded by the leading
# boundary: the receiver has to be exactly `Log` (or `::Log`).
private GLOBAL_LOG_CALL = /(?:^|[^[:alnum:]_.])(?:::)?Log\.(?:trace|debug|info|notice|warn|error|fatal)\b/

describe "stdout purity" do
  describe "the global Log" do
    it "is never used as a diagnostic sink anywhere in src/" do
      offenders = [] of String
      stripped_sources.each do |path, lines|
        lines.each do |(number, line)|
          offenders << "#{path}:#{number}: #{line.strip}" if line.matches?(GLOBAL_LOG_CALL)
        end
      end

      # `Log.debug` in `llm/cache.cr` and the GraphQL file hook were the last
      # two. Both were also dead: nothing in Noir lowers the global logger's
      # `Info` threshold, so they could never print — a diagnostic aimed at the
      # report stream that also reported nothing. Diagnostics go through
      # `NoirLogger` (STDERR, honouring `--debug`), coverage losses through
      # `Noir::SkippedFiles`.
      offenders.should be_empty
    end

    it "is redirected to STDERR before the CLI does anything else" do
      # Order matters more than it looks: the redirect has to land before any
      # code can log, so it is the first statement of `Router.dispatch` rather
      # than something a later subcommand opts into.
      body = File.read("src/cli/router.cr")
      after_signature = body.split("def self.dispatch", 2)[1]?
      after_signature.should_not be_nil

      # `[1..]` drops the remainder of the `def` line itself (the parameter
      # list), leaving the method body.
      statements = after_signature.not_nil!.lines[1..]
        .map(&.strip)
        .reject { |line| line.empty? || line.starts_with?('#') }
      statements.first?.should eq("Noir::CLI.route_library_logs_to_stderr!")
    end

    it "binds a STDERR backend, not the stdlib's STDOUT default" do
      # Restored afterwards to the level Crystal's spec DSL installs, so this
      # example cannot make the rest of the suite noisy.
      Noir::CLI.route_library_logs_to_stderr!
      backend = ::Log.for("noir.stdout_purity_spec").backend
      backend.should be_a(::Log::IOBackend)
      backend.as(::Log::IOBackend).io.should be(STDERR)
    ensure
      ::Log.setup(::Log::Severity::None)
    end
  end
end
