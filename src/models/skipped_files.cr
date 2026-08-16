require "./analyzer_failure"

# Files an analyzer opened and could not finish, tallied per tech.
#
# `AnalyzerFailure` covers the case where a whole analyzer raised: coverage
# lost by the tech. The other half of the same problem is a single file
# raising inside an analyzer that otherwise completed — the per-file rescues in
# `Analyzer#parallel_analyze` and `Analyzer#scan_files` exist precisely so one
# unreadable or unparsable file costs only itself. That is the right
# behaviour, but until now the only trace was a `--debug` line, so the result
# of a scan that silently dropped a file was byte-identical to one that read
# everything.
#
# #2612 made that gap wider by adding a ceiling on parse time: a
# pathologically malformed file now raises and is skipped where it used to
# take the process down. Loud-and-fatal became quiet-and-partial, which is the
# better failure mode only if the "partial" part is visible somewhere.
#
# Tallied rather than listed one entry per file: a repository that trips this
# usually trips it in bulk (a vendored minified bundle, a generated tree), and
# `errors` is part of the JSON/YAML/TOML output — one entry per tech with a
# count and a few example paths says the same thing without letting a broken
# checkout print thousands of lines.
module Noir::SkippedFiles
  extend self

  # Example paths kept per tech. Beyond this only the count grows.
  MAX_PATHS_PER_TECH = 5

  private class Tally
    property count = 0
    property reason = ""
    getter paths = [] of String
  end

  @@tallies = {} of String => Tally
  @@mutex = Mutex.new

  # `tech` may be empty — `Analyzer`'s own `tech` returns `""` and only
  # `analyzer_for` fills it in, so a base-class caller is still recorded,
  # just unattributed.
  def record(tech : String, path : String, reason : String) : Nil
    @@mutex.synchronize do
      tally = @@tallies[tech] ||= Tally.new
      tally.count += 1
      tally.reason = reason if tally.reason.empty?
      tally.paths << path if tally.paths.size < MAX_PATHS_PER_TECH
    end
  end

  # Cleared at the start of every analysis pass: diff mode runs two, and an
  # embedder can call `analyze` twice on one runner. A tally carried over
  # would report the previous codebase's skips — and, under `--strict`, fail
  # the build for them forever after.
  def clear : Nil
    @@mutex.synchronize { @@tallies.clear }
  end

  # Total files skipped since the last `clear`, across every tech.
  def count : Int32
    @@mutex.synchronize { @@tallies.values.sum(&.count) }
  end

  # One `AnalyzerFailure` per tech that skipped at least one file, so a
  # dropped file lands in the same `errors` array — and the same `--strict`
  # exit code — as a dropped analyzer.
  def failures : Array(AnalyzerFailure)
    @@mutex.synchronize do
      @@tallies.map do |tech, tally|
        AnalyzerFailure.new(tech, message_for(tally))
      end
    end
  end

  private def message_for(tally : Tally) : String
    noun = tally.count == 1 ? "file" : "files"
    examples = tally.paths.join(", ")
    hidden = tally.count - tally.paths.size
    examples += " (+#{hidden} more)" if hidden > 0
    "skipped #{tally.count} #{noun}: #{examples}; first error: #{tally.reason}"
  end
end
