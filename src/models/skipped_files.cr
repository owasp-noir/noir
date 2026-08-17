require "./analyzer_failure"

# Every path by which a scan can quietly lose coverage, funnelled into one
# place.
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
# The analysis pass was only ever half the story, though. A scan drops
# coverage in six other places — an unlistable directory takes its whole
# subtree, an oversize or unreadable or binary-looking file is filtered out, a
# symlinked tree is never walked, an export never lands, `-P` runs with zero
# rules loaded — and each of those had its own local counter, its own log
# line, and no route into `errors` at all. So `--strict` (documented as "exit
# 2 if any analyzer failed *or skipped a file*") reported green on a scan that
# had lost most of a codebase.
#
# Rather than six more counters, they all record here. `failures` is the one
# list, `errors` in the output is that list, and `degraded` in the CLI is
# "that list is not empty". Adding a seventh drop path is a `record` call.
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

  # Labels for the drop paths that belong to no analyzer. They land in the
  # same `errors[].tech` field a real tech name would, because the field
  # answers the same question either way: which part of the scan came up
  # short.
  DETECT_SCOPE       = "detect"
  DELIVER_SCOPE      = "deliver"
  PASSIVE_SCAN_SCOPE = "passive-scan"

  # Which `clear` a gap answers to. The phase is a lifecycle marker only — it
  # does not appear in the output — because the two halves of a scan are
  # reset at different moments.
  enum Phase
    # The detection walk, delivery/export, and rule loading: the parts that
    # run once around the analysis pass. Dropped when a new detection pass
    # starts, which is where a scan of a new codebase begins.
    Scan

    # The analysis pass. Dropped at the top of every `analysis_endpoints`
    # call: diff mode runs two, and an embedder can call `analyze` twice on
    # one runner. A tally carried over would report the previous codebase's
    # skips — and, under `--strict`, fail the build for them forever after.
    Analysis
  end

  private class Tally
    property scope = ""
    property noun = "file"
    property phase = Phase::Analysis
    property count = 0
    property reason = ""
    getter paths = [] of String
  end

  # A gap with no per-item granularity — an export that never landed, a rule
  # set that loaded nothing. Nothing to tally and no example paths to show,
  # so the message is carried verbatim.
  private class Gap
    getter scope : String
    getter message : String
    getter phase : Phase

    def initialize(@scope : String, @message : String, @phase : Phase)
    end
  end

  @@tallies = {} of String => Tally
  @@gaps = [] of Gap
  @@mutex = Mutex.new

  # `tech` may be empty — `Analyzer`'s own `tech` returns `""` and only
  # `analyzer_for` fills it in, so a base-class caller is still recorded,
  # just unattributed.
  #
  # `noun` names what was dropped so the message reads true for callers that
  # skip something other than a file — a directory that would not list, a
  # symlink that is not followed.
  def record(tech : String, path : String, reason : String,
             noun : String = "file", phase : Phase = Phase::Analysis) : Nil
    @@mutex.synchronize do
      tally = @@tallies[bucket_key(tech, noun)] ||= begin
        fresh = Tally.new
        fresh.scope = tech
        fresh.noun = noun
        fresh.phase = phase
        fresh
      end
      tally.count += 1
      tally.reason = reason if tally.reason.empty?
      tally.paths << path if tally.paths.size < MAX_PATHS_PER_TECH
    end
  end

  # One-off coverage gap, reported as written. Use `record` instead whenever
  # the loss is per-path and can arrive in bulk.
  def record_gap(scope : String, message : String, phase : Phase = Phase::Scan) : Nil
    @@mutex.synchronize { @@gaps << Gap.new(scope, message, phase) }
  end

  # Drops everything, both phases. Used by specs and by library callers that
  # want a clean slate; production code clears one phase at a time.
  def clear : Nil
    @@mutex.synchronize do
      @@tallies.clear
      @@gaps.clear
    end
  end

  def clear(phase : Phase) : Nil
    @@mutex.synchronize do
      @@tallies.reject! { |_, tally| tally.phase == phase }
      @@gaps.reject! { |gap| gap.phase == phase }
    end
  end

  # Total files (and directories, and symlinks) skipped since the last
  # `clear`, across every scope. Excludes `record_gap` entries, which count
  # no items.
  def count : Int32
    @@mutex.synchronize { @@tallies.values.sum(&.count) }
  end

  # One `AnalyzerFailure` per tally plus one per recorded gap, so a dropped
  # file, an unwalked directory and an undelivered export all land in the
  # same `errors` array — and the same `--strict` exit code — as a dropped
  # analyzer.
  def failures : Array(AnalyzerFailure)
    @@mutex.synchronize { build_failures(@@tallies.values, @@gaps) }
  end

  def failures(phase : Phase) : Array(AnalyzerFailure)
    @@mutex.synchronize do
      build_failures(@@tallies.values.select { |tally| tally.phase == phase },
        @@gaps.select { |gap| gap.phase == phase })
    end
  end

  private def build_failures(tallies : Array(Tally), gaps : Array(Gap)) : Array(AnalyzerFailure)
    result = tallies.map { |tally| AnalyzerFailure.new(tally.scope, message_for(tally)) }
    gaps.each { |gap| result << AnalyzerFailure.new(gap.scope, gap.message) }
    result
  end

  # Tally identity. The noun is part of the key so a scope that lost both a
  # directory and a file reports both, rather than merging them under
  # whichever noun happened to arrive first.
  private def bucket_key(tech : String, noun : String) : String
    "#{tech}/#{noun}"
  end

  private def message_for(tally : Tally) : String
    noun = pluralize(tally.noun, tally.count)
    examples = tally.paths.join(", ")
    hidden = tally.count - tally.paths.size
    examples += " (+#{hidden} more)" if hidden > 0
    "skipped #{tally.count} #{noun}: #{examples}; first error: #{tally.reason}"
  end

  private def pluralize(noun : String, count : Int32) : String
    return noun if count == 1
    noun.ends_with?('y') ? "#{noun[0...-1]}ies" : "#{noun}s"
  end
end
